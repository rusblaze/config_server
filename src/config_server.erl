%% -*- encoding: utf-8 -*-
-module(config_server).
-author("rusblaze").
-behaviour(gen_server).

%%======================================================================
%% API functions
%%======================================================================
-export([
        %% Start/Stop functions
          start/0
        , start/1
        , start_link/0
        , start_link/1
        , stop/0
        %% Get functions
        , get_component_config/1
        , get_component_config/2
        %% Set functions
        , set_component_config/2
        , set_config/1
        , reload_config/0
        %% Subscription manage functions
        , subscribe/2
        , unsubscribe/1
        %% Monitoring
        , print_info/0
        ]).

%%======================================================================
%% Callback functions
%%======================================================================
-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

%%======================================================================
%% Types
%%======================================================================
-type section() :: atom() | string().
-export_type([section/0]).

-type section_path() :: list(section()).
-export_type([section_path/0]).

%%======================================================================
%% Macro
%%======================================================================
-define(COMMON_CONFIG_FILE_NAME,      "common.config").
-define(ENVIRONMENT_CONFIG_FILE_NAME, "env.config").

%%======================================================================
%% API functions
%%======================================================================
%%----------------------------------------------------------------------
%% Start/Stop functions
%%----------------------------------------------------------------------
start() ->
    {ok, Application} = application:get_application(),
    PrivDir = code:priv_dir(Application),
    case PrivDir of
        {error, bad_name} ->
            {error, no_priv_dir};
        _DirName ->
            ?MODULE:start([{priv_dir, PrivDir}])
    end.

start(Args) ->
    gen_server:start({local,?MODULE}, ?MODULE, Args, []).

start_link() ->
    {ok, Application} = application:get_application(),
    start_link(Application).

start_link(Application) when is_atom(Application) ->
  PrivDir = code:priv_dir(Application),
  case PrivDir of
    {error, bad_name} ->
      {error, no_priv_dir};
    DirName ->
      ?MODULE:start_link([{priv_dir, DirName}])
  end;

start_link(Args) ->
    case gen_server:start_link({local,?MODULE}, ?MODULE, Args, []) of
        {error, {already_started, Pid}} ->
            link(Pid),
            {ok, Pid};
        Other ->
            Other
    end.

stop() ->
    gen_server:call(?MODULE, stop).

%%----------------------------------------------------------------------
%% Get functions
%%----------------------------------------------------------------------
-spec get_component_config(Section :: section_path()) -> Result when
    Result :: {ok, Value :: term()}
             | error.
get_component_config(Section) ->
    gen_server:call(?MODULE, {get_component_config, Section}, 1000).

-spec get_component_config(Section :: section_path(), Default :: term()) -> Result when
    Result :: {ok, Value :: term()}.
get_component_config(Section, Default) ->
    gen_server:call(?MODULE, {get_component_config, Section, Default}, 1000).

%%----------------------------------------------------------------------
%% Set functions
%%----------------------------------------------------------------------
-spec set_component_config(Section :: section_path(), Value :: term()) -> no_return().
set_component_config(Section, Value) ->
    gen_server:cast(?MODULE, {set_component_config, Section, Value}).

reload_config() ->
    ok.

set_config(_NewConfig) ->
    ok.

%%----------------------------------------------------------------------
%% Subscription manage functions
%%----------------------------------------------------------------------
-spec subscribe(PidOrNameOrFun, Section) -> {ok, reference()} when
      PidOrNameOrFun :: pid()
                      | module()
                      | fun((...) -> no_return())
    , Section        :: section_path().
subscribe(PidOrNameOrFun, Section) when   erlang:is_pid(PidOrNameOrFun)
                                        ; erlang:is_atom(PidOrNameOrFun)
                                        ; erlang:is_function(PidOrNameOrFun) ->
    gen_server:call(?MODULE, {subscribe, PidOrNameOrFun, Section});
subscribe(PidOrNameOrFun, _Section) ->
    {error, {wrong_type, PidOrNameOrFun}}.

-spec unsubscribe(Ref :: reference()) -> ok | {error, no_ref}.
unsubscribe(Ref) when erlang:is_reference(Ref) ->
    gen_server:call(?MODULE, {unsubscribe, Ref});
unsubscribe(Ref) ->
    {error, {wrong_type, Ref}}.

%%----------------------------------------------------------------------
%% Monitoring
%%----------------------------------------------------------------------
print_info() ->
    gen_server:call(?MODULE, print_info).

%%======================================================================
%% Callback functions
%%======================================================================
init(Args) ->
    process_flag(trap_exit, true),

    PrivDir = proplists:get_value(priv_dir, Args),
    ConfDir = PrivDir ++ "/configs/",
    {ok, [CommonConfig]} = file:consult(ConfDir ++ ?COMMON_CONFIG_FILE_NAME),
    {ok, [EnvConfig]}    = file:consult(ConfDir ++ ?ENVIRONMENT_CONFIG_FILE_NAME),

    Merged = deep_merge(CommonConfig, EnvConfig),

    % Replacements = #{"%priv%" => PrivDir},

    {ok, #{ path        => ConfDir
          , config      => Merged
          , subscribers => #{}
          }
    }.

handle_call({get_component_config, SectionPath}, _From, #{config := Config} = StateData) ->
    Reply =
        case xpath(SectionPath, Config) of
            error -> error;
            Other -> {ok, Other}
        end,

    {reply, Reply, StateData};

handle_call({get_component_config, SectionPath, Default}, _From, #{config := Config} = StateData) ->
    Reply =
        case xpath(SectionPath, Config) of
            error -> {ok, Default};
            Other -> {ok, Other}
        end,

    {reply, Reply, StateData};

handle_call(print_info, _From, StateData) ->
    {reply, ok, StateData};

handle_call(stop, _From, StateData) ->
    {stop, stop_on_call, ok, StateData};

handle_call({subscribe, PidOrNameOrFun, SectionPath}, _From, #{subscribers := Subscribers} = StateData) ->
    Ref = erlang:make_ref(),
    if
        erlang:is_pid(PidOrNameOrFun) ->
            Value = #{type => pid, subscriber => PidOrNameOrFun};
        erlang:is_atom(PidOrNameOrFun) ->
            Value = #{type => name, subscriber => PidOrNameOrFun};
        true ->
            Value = #{type => function, subscriber => PidOrNameOrFun}
    end,

    OldSubscribersList = maps:get(SectionPath, Subscribers, #{}),
    NewSubscribersList = maps:put(Ref, Value, OldSubscribersList),
    NewSubscribers = maps:put(SectionPath, NewSubscribersList, Subscribers),
    NewStateData = maps:put(subscribers, NewSubscribers, StateData),

    {reply, {ok, Ref}, NewStateData};

handle_call({unsubscribe, Ref}, _From, #{subscribers := Subscribers} = StateData) ->
    NewSubscribers = maps:map( fun(_SectionPath, SubscribersList) ->
                                   maps:without([Ref], SubscribersList)
                               end
                             , Subscribers
                             ),

    NewStateData = maps:put(subscribers, NewSubscribers, StateData),
    {reply, {ok, Ref}, NewStateData};

handle_call(Request, _From, StateData) -> {reply, {error, {unknown_command, Request}}, StateData}.

handle_cast( {set_component_config, SectionPath, NewValue}
           , #{ config      := Config
              , subscribers := Subscribers
              } = StateData
           ) ->
    OldValue = case xpath(SectionPath, Config) of
                   error -> error;
                   Other -> Other
               end,
    NewConfig = xpath_store(SectionPath, NewValue, Config),
    notify_subscribers(SectionPath, OldValue, NewValue, Subscribers),

    {noreply, maps:put(config, NewConfig, StateData)};


handle_cast(_Request, State) -> {noreply, State}.

handle_info(_Info, State) -> {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%======================================================================
%% Internal functions
%%======================================================================
recursive_merge_values([], BaseConfig, _EnvConfig) ->
    BaseConfig;
recursive_merge_values([Key | Keys], BaseConfig, EnvConfig) ->
    NewBaseConfig = recursive_merge_value(Key, BaseConfig, EnvConfig),
    recursive_merge_values(Keys, NewBaseConfig, EnvConfig).

recursive_merge_value(Key, BaseConfig, EnvConfig) ->
    BaseConfigValue = maps:get(Key, BaseConfig, undefined),
    EnvConfigValue  = maps:get(Key, EnvConfig, undefined),

    case {BaseConfigValue, EnvConfigValue} of
        {_, undefined} ->
            BaseConfig;
        {undefined, _} ->
            maps:put(Key, EnvConfigValue, BaseConfig);
        {BaseConfigValue, EnvConfigValue} when is_map(BaseConfigValue) andalso is_map(EnvConfigValue) ->
            maps:put(Key, deep_merge(BaseConfigValue, EnvConfigValue), BaseConfig);
        {BaseConfigValue, EnvConfigValue} ->
            maps:put(Key, EnvConfigValue, BaseConfig)
    end.

deep_merge(BaseConfig, EnvConfig) when is_map(BaseConfig) andalso is_map(EnvConfig) ->
    Keys = maps:keys(BaseConfig),
    NewBaseConfig = recursive_merge_values(Keys, BaseConfig, EnvConfig),
    recursive_merge_values(Keys, EnvConfig, NewBaseConfig);
deep_merge(_BaseConfig, _EnvConfig) ->
    throw("Bad config").


notify_subscribers(SectionPath, OldValue, NewValue, Subscribers) ->
    SubscribersList = maps:get(SectionPath, Subscribers, #{}),
    maps:fold( fun(Ref, Subscriber, AccIn) ->
                   case Subscriber of
                       #{type := pid, subscriber := Pid} ->
                           Pid ! {?MODULE, #{section => SectionPath, old => OldValue, new => NewValue}},
                           AccIn;
                       #{type := name, subscriber := Name} ->
                           try
                               ok = Name:notify_config(SectionPath, OldValue, NewValue),
                               AccIn
                           catch
                               Ec:Ee ->
                                   Error = maps:put(Ref, {Ec,Ee}, #{}),
                                   [Error | AccIn]
                           end;
                       #{type := function, subscriber := Fun} ->
                           try
                               Fun(SectionPath, OldValue, NewValue),
                               AccIn
                           catch
                               Ec:Ee ->
                                   Error = maps:put(Ref, {Ec,Ee}, #{}),
                                   [Error | AccIn]
                           end
                   end
               end
             , []
             , SubscribersList
             ).

% merge_configs(CommonConfig, EnvConfig, Replacements) ->
%     Merged = orddict:merge(fun(_Key, CommonSection, EnvSection) ->
%                                merge_config_section( CommonSection
%                                                    , EnvSection
%                                )
%                            end,
%                            CommonConfig,
%                            EnvConfig),
%     Replaced = replace(Merged, Replacements),

%     {ok, Replaced}.

% merge_config_section(CCSection, ECSection) when is_list(CCSection), is_list(ECSection) ->
%     orddict:merge(fun(_Key, CommonValue, EnvValue) when is_list(CommonValue), is_list(EnvValue) ->
%                           {ok, Merged} = merge_configs(CommonValue, EnvValue, []),
%                           Merged;
%                      (_Key, _CommonValue, EnvValue) ->
%                               EnvValue
%                   end,
%                   CCSection,
%                   ECSection);

% merge_config_section(_CCSection, ECSection) ->
%     ECSection.

% replace({Key, Value}, []) ->
%     {Key, Value};

% replace({Key, Value}, [{Re, Replacement} | ReplacementsTail] = Replacements) ->
%     case io_lib:printable_latin1_list(Value) or io_lib:printable_unicode_list(Value) of
%        true ->
%            replace({Key, re:replace(Value, Re, Replacement, [global, {return, list}])}, ReplacementsTail);
%        false ->
%            {Key, replace(Value, Replacements)}
%     end;

% replace(Config, Replacements) when is_list(Config) ->
%     case io_lib:printable_latin1_list(Config) or io_lib:printable_unicode_list(Config) of
%        true ->
%            Config;
%        false ->
%            lists:map( fun({K, V}) ->
%                             replace({K, V}, Replacements);
%                          (L) when is_list(L) ->
%                             replace(L, Replacements);
%                          (Other) ->
%                             Other
%                        end
%                      , Config
%                      )
%     end;

% replace(Config, _) ->
%     Config.

xpath([Section | []], Config) ->
    case maps:get(Section, Config, <<>>) of
        <<>> ->
            error_logger:error_msg("xpath... Can't find ~p", [Section]),
            error;
        Other ->
            Other
    end;
xpath([Section | SectionPath], Config) ->
    case maps:get(Section, Config, <<>>) of
        <<>> ->
            error_logger:error_msg("xpath... Can't find ~p", [Section]),
            error;
        ConfigSubMap when is_map(ConfigSubMap) ->
            xpath(SectionPath, ConfigSubMap);
        Other ->
            error_logger:error_msg("xpath... Can't find ~p in ~p", [SectionPath, Other]),
            error
    end.


xpath_store([Section | []], Value, Config) ->
    maps:put(Section, Value, Config);

xpath_store([Section | SectionPath], Value, Config) ->
    ConfigSubTree =
        case maps:get(Section, Config, <<>>) of
            <<>> ->
                #{};
            ConfigSubMap when is_map(ConfigSubMap) ->
                ConfigSubMap;
            Other ->
                error_logger:error_msg("Can't replace ~p with map", [Other]),
                error
        end,
    maps:put(Section, xpath_store(SectionPath, Value, ConfigSubTree), Config).

% to_orddict(Config) when is_list(Config) ->
%     ConfigDict = lists:filter( fun({_Key, _Value}) -> true;
%                                   (_Other) -> false
%                                end,
%                                Config
%                              ),
%     case ConfigDict of
%         [] ->
%             Config;
%         _Other ->
%             ConfigOrdDict = orddict:from_list(ConfigDict),
%             orddict:map(fun(_Key, Value) -> to_orddict(Value) end, ConfigOrdDict)
%     end;

% to_orddict(Config) ->
%     Config.

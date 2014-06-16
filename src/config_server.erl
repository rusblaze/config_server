%% -*- encoding: utf-8 -*-
-module(config_server).
-behaviour(gen_server).

%%======================================================================
%% API functions
%%======================================================================
-export([ start/0
        , start/1
        , start_link/0
        , start_link/1
        , stop/0
        , get_component_config/1
        , get_component_config/2
        , set_component_config/2
        , subscribe/2
        , set_config/1
        , reload_config/0
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

-type section() :: atom() | string().

-record(sub_callback, {pid :: pid()}).

-record(state, { path        :: string()
               , config      :: orddict:orddict()
               , subscribers :: orddict:orddict()
               }).

-define(COMMON_CONFIG_FILE_NAME,      "common.config").
-define(ENVIRONMENT_CONFIG_FILE_NAME, "env.config").

%%======================================================================
%% API functions
%%======================================================================
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
    PrivDir = code:priv_dir(Application),
    case PrivDir of
        {error, bad_name} ->
            {error, no_priv_dir};
        DirName ->
            ?MODULE:start_link([{priv_dir, DirName}])
    end.

start_link(Args) ->
    case gen_server:start_link({local,?MODULE}, ?MODULE, Args, []) of
        {error, {already_started, Pid}} ->
            link(Pid),
            {ok, Pid};
        Other ->
            Other
    end.

-spec get_component_config(Section :: [section()]) -> Result when
    Result :: {ok, Value :: term()}
             | error.
get_component_config(Section) ->
    gen_server:call(?MODULE, {get_component_config, Section}, 1000).

-spec get_component_config(Section :: [section()], Default :: term()) -> Result when
    Result :: {ok, Value :: term()}.

get_component_config(Section, Default) ->
    gen_server:call(?MODULE, {get_component_config, Section, Default}, 1000).

set_component_config(Section, Value) ->
    gen_server:cast(?MODULE, {set_component_config, Section, Value}).

-spec subscribe(Pid, Section) -> no_return() when
      Pid      :: pid()
    , Section :: [section()].
subscribe(Pid, Section) ->
    gen_server:cast(?MODULE, {subscribe, Pid, Section}).

reload_config() ->
    ok.

set_config(_NewConfig) ->
    ok.

print_info() ->
    gen_server:call(?MODULE, print_info).

stop() ->
    gen_server:call(?MODULE, stop).
%%======================================================================
%% Callback functions
%%======================================================================
init(Args) ->
    process_flag(trap_exit, true),

    PrivDir = proplists:get_value(priv_dir, Args),
    ConfDir = PrivDir ++ "/configs/",
    {ok, [CommonConfig]} = file:consult(ConfDir ++ ?COMMON_CONFIG_FILE_NAME),
    {ok, [EnvConfig]}    = file:consult(ConfDir ++ ?ENVIRONMENT_CONFIG_FILE_NAME),

    Replacements = [{"%priv%", PrivDir}],

    CommonConfigDict = to_orddict(CommonConfig),
    EnvConfigDict    = to_orddict(EnvConfig),

    {ok, Config} = merge_configs( CommonConfigDict
                                , EnvConfigDict
                                , Replacements
                                ),

    {ok, #state{ path        = ConfDir
               , config      = Config
               , subscribers = orddict:new()
               }
    }.

handle_call({get_component_config, SectionPath}, _From, #state{config=Config} = State) ->
    Reply =
        case xpath(SectionPath, Config) of
            error -> error;
            Other -> Other
        end,

    {reply, Reply, State};

handle_call({get_component_config, SectionPath, Default}, _From, #state{config=Config} = State) ->
    Reply =
        case xpath(SectionPath, Config) of
            error -> {ok, Default};
            Other -> Other
        end,

    {reply, Reply, State};

handle_call(print_info, _From, State) ->
    {reply, ok, State};

handle_call(stop, _From, State) ->
    {stop, stop_on_call, ok, State};

handle_call(Request, _From, State) -> {reply, {error, {unknown_command, Request}}, State}.

handle_cast({set_component_config, SectionPath, Value}, #state{ config=Config
                                                              , subscribers=Subscribers
                                                              } = State) ->
    NewConfig = xpath_store(SectionPath, Value, Config),

    notify_subscribers(SectionPath, Subscribers),

    {noreply, State#state{config=NewConfig}};

handle_cast({subscribe, Pid, SectionPath}, #state{subscribers=Subscribers} = State) ->
    Callback = #sub_callback{pid = Pid},

    NewSectionSubscribers =
        case orddict:find(SectionPath, Subscribers) of
            error -> % no subscribers for this section
                [Callback];
            {ok, SectionSubscribers} ->
                case lists:member(Callback, SectionSubscribers) of
                    true ->
                        SectionSubscribers;
                    false ->
                        [Callback | SectionSubscribers]
                end
        end,

    NewSubscribers = orddict:store(SectionPath, NewSectionSubscribers, Subscribers),

    {noreply, State#state{subscribers=NewSubscribers}};

handle_cast(_Request, State) -> {noreply, State}.

handle_info(_Info, State) -> {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%======================================================================
%% Internal functions
%%======================================================================
notify_subscribers(SectionPath, AllSubscribers) ->
    case orddict:find(SectionPath, AllSubscribers) of
        error ->
            ok;
        {ok, Subscribers} ->
            lists:foreach( fun(#sub_callback{pid=Pid}) ->
                                   Pid ! {?MODULE, SectionPath};
                               (WrongCallback) ->
                                   error_logger:info_msg("Wrong callback ~p", [WrongCallback])
                           end
                         , Subscribers
                         )
    end.

merge_configs(CommonConfig, EnvConfig, Replacements) ->
    Merged = orddict:merge(fun(_Key, CommonSection, EnvSection) ->
                               merge_config_section( CommonSection
                                                   , EnvSection
                               )
                           end,
                           CommonConfig,
                           EnvConfig),
    Replaced = replace(Merged, Replacements),

    {ok, Replaced}.

merge_config_section(CCSection, ECSection) when is_list(CCSection), is_list(ECSection) ->
    orddict:merge(fun(_Key, CommonValue, EnvValue) when is_list(CommonValue), is_list(EnvValue) ->
                          {ok, Merged} = merge_configs(CommonValue, EnvValue, []),
                          Merged;
                     (_Key, _CommonValue, EnvValue) ->
                              EnvValue
                  end,
                  CCSection,
                  ECSection);

merge_config_section(_CCSection, ECSection) ->
    ECSection.

replace({Key, Value}, []) ->
    {Key, Value};

replace({Key, Value}, [{Re, Replacement} | ReplacementsTail] = Replacements) ->
    case io_lib:printable_latin1_list(Value) or io_lib:printable_unicode_list(Value) of
       true ->
           replace({Key, re:replace(Value, Re, Replacement, [global, {return, list}])}, ReplacementsTail);
       false ->
           {Key, replace(Value, Replacements)}
    end;

replace(Config, Replacements) when is_list(Config) ->
    case io_lib:printable_latin1_list(Config) or io_lib:printable_unicode_list(Config) of
       true ->
           Config;
       false ->
           lists:map( fun({K, V}) ->
                            replace({K, V}, Replacements);
                         (L) when is_list(L) ->
                            replace(L, Replacements);
                         (Other) ->
                            Other
                       end
                     , Config
                     )
    end;

replace(Config, _) ->
    Config.

xpath([Section | []], Config) ->
    orddict:find(Section, Config);

xpath([Section | SectionPath], Config) ->
    case orddict:find(Section, Config) of
        {ok, ConfigSubTree} when is_list(ConfigSubTree) ->
            xpath(SectionPath, ConfigSubTree);
        Other ->
            error_logger:error_msg("xpath... Can't search ~p in ~p", [SectionPath, Other]),
            error
    end.


xpath_store([Section | []], Value, Config) ->
    orddict:store(Section, Value, Config);

xpath_store([Section | SectionPath], Value, Config) ->
    ConfigSubTree =
        case orddict:find(Section, Config) of
            error ->
                orddict:new();
            {ok, Other} ->
                Other
        end,
    orddict:store(Section, xpath_store(SectionPath, Value, ConfigSubTree), Config).

to_orddict(Config) when is_list(Config) ->
    ConfigDict = lists:filter( fun({_Key, _Value}) -> true;
                                  (_Other) -> false
                               end,
                               Config
                             ),
    case ConfigDict of
        [] ->
            Config;
        _Other ->
            ConfigOrdDict = orddict:from_list(ConfigDict),
            orddict:map(fun(_Key, Value) -> to_orddict(Value) end, ConfigOrdDict)
    end;

to_orddict(Config) ->
    Config.

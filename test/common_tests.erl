%% -*- encoding: utf-8 -*-
%%=============================================================================
%% @doc Common application tests.
%%
%% @copyright 2014
%%
%%=============================================================================
-module(common_tests).
-author("aivanov").

%%=============================================================================
%% Includes
%%=============================================================================
-include_lib("eunit/include/eunit.hrl").

basic_test_() ->
    { setup
    , fun setup/0
    , fun cleanup/1
    , [ fun get_conf/0
      , fun get_set_get_conf/0
      , fun subscribtion_testing/0
      ]
    }.

setup() ->
    PrivDir = code:priv_dir(config_server),
    config_server:start([{priv_dir, PrivDir}]).

cleanup(_) ->
    ok = config_server:stop().

get_conf() ->
    ?assert(error == config_server:get_component_config([some, unknown, section])),
    ?assert({ok, "default value"} == config_server:get_component_config([some, unknown, section], "default value")).

get_set_get_conf() ->
    ?assert(error == config_server:get_component_config([some, unknown, section])),
    config_server:set_component_config([some, unknown, section], "default value"),
    ?assert({ok, "default value"} == config_server:get_component_config([some, unknown, section])).

subscribtion_testing() ->
    config_server:subscribe(self(), [some, unknown, section]),
    ChangedValue = "changed value",
    config_server:set_component_config([some, unknown, section], ChangedValue),
    receive
        {config_server, [some, unknown, section]} ->
            ?assert({ok, ChangedValue} == config_server:get_component_config([some, unknown, section]))
    end.

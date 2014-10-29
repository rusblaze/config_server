%% -*- encoding: utf-8 -*-
%%=============================================================================
%% @doc Common application tests.
%%
%% @copyright 2014
%%
%%=============================================================================
-module(common_tests).
-author("rusblaze").

%%=============================================================================
%% Includes
%%=============================================================================
-include_lib("eunit/include/eunit.hrl").

start_stop_test_() ->
    [ fun start_stop/0
    ].

basic_test_() ->
    { setup
    , fun setup/0
    , fun cleanup/1
    , [ fun get_conf/0
      , fun get_set_get_conf/0
      ]
    }.

setup() ->
    PrivDir = code:priv_dir(config_server),
    config_server:start([{priv_dir, PrivDir}]).

cleanup(_) ->
    ok = config_server:stop().

start_stop() ->
    PrivDir = code:priv_dir(config_server),
    {ok,Pid1} = config_server:start([{priv_dir, PrivDir}]),
    ?assert(erlang:is_pid(Pid1)),
    ?assert(ok == config_server:stop()),
    {ok, Pid2} = config_server:start_link([{priv_dir, PrivDir}]),
    ?assert(erlang:is_pid(Pid2)),
    erlang:unlink(Pid2),
    ?assert(ok == config_server:stop()).
    % ?assert({ok, "default value"} == config_server:get_component_config([some, unknown, section], "default value")).

get_conf() ->
    ?assert(error == config_server:get_component_config([some, unknown, section])),
    ?assert({ok, "default value"} == config_server:get_component_config([some, unknown, section], "default value")).

get_set_get_conf() ->
    ?assert(error == config_server:get_component_config([some, unknown, section])),
    config_server:set_component_config([some, unknown, section], "default value"),
    ?assert({ok, "default value"} == config_server:get_component_config([some, unknown, section])).

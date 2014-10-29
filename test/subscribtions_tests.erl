%% -*- encoding: utf-8 -*-
%%=============================================================================
%% @doc Subscriptions tests.
%%
%% @copyright 2014
%%
%%=============================================================================
-module(subscribtions_tests).
-author("rusblaze").

%%=============================================================================
%% Includes
%%=============================================================================
-include_lib("eunit/include/eunit.hrl").

%%=============================================================================
%% Tests
%%=============================================================================
basic_test_() ->
    { setup
    , fun setup/0
    , fun cleanup/1
    , [ fun subscribtion_testing/0
      ]
    }.

setup() ->
    PrivDir = code:priv_dir(config_server),
    config_server:start([{priv_dir, PrivDir}]).

cleanup(_) ->
    ok = config_server:stop().

subscribtion_testing() ->
    Section = [some, section],
    config_server:subscribe(self(), Section),
    ChangedValue = "changed value",
    config_server:set_component_config(Section, ChangedValue),
    receive
        {config_server, #{section := SP, old := _OldValue, new := NewValue}} ->
            ?assertEqual(Section, SP),
            ?assertEqual(ChangedValue, NewValue),
            ?assert({ok, ChangedValue} == config_server:get_component_config(Section))
    end.

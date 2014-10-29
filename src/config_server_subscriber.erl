%% -*- encoding: utf-8 -*-
-module(config_server_subscriber).
-author("rusblaze").

%%======================================================================
%% Callbacks
%%======================================================================
-callback notify_config(SectionPath, OldValue, NewValue) -> ok when
      SectionPath :: config_server:section_path()
    , OldValue    :: term()
    , NewValue    :: term().

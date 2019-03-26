%%%-------------------------------------------------------------------
%% @doc grpcbox public API
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_app).

-behaviour(application).

-export([start/2, stop/1, config_change/3]).

-include("grpcbox.hrl").

start(_StartType, _StartArgs) ->
    {ok, Pid} = grpcbox_sup:start_link(),
    case application:get_env(grpcbox, client) of
        {ok, #{channels := Channels}} ->
            [grpcbox_channel_sup:start_child(Name, Endpoints, Options)
             || {Name, Endpoints, Options} <- Channels];
        _ ->
            ok
    end,

    ServerOpts = application:get_env(grpcbox, servers, []),
    maybe_start_server(ServerOpts),

    {ok, Pid}.

stop(_State) ->
    _ = maybe_erase_user_agent(),
    ok.

config_change(_Changed, _New, _Removed) ->
    _ = maybe_erase_user_agent(),
    ok.

%%

maybe_erase_user_agent() ->
    case erlang:function_exported(persistent_term, erase, 1) of
        true ->
            persistent_term:erase('$grpcbox_user_agent');
        false ->
            false
    end.

maybe_start_server([]) ->
    ok;
maybe_start_server([ServerOpts | Tail]) ->
    grpcbox_services_simple_sup:start_child(ServerOpts),
    maybe_start_server(Tail).

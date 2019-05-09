% -record(data, {endpoint :: grpcbox_channel:endpoint(),
%                channel :: grpcbox_channel:t(),
%                info :: #{authority := binary(),
%                          scheme := binary(),
%                          encoding := grpcbox:encoding(),
%                          stats_handler := module() | undefined
%                         },
%                conn :: pid() | undefined,
%                idle_interval :: timer:time()}).

%%%-------------------------------------------------------------------
%% @doc grpcbox subchannel API
%% See [https://grpc.io/blog/a_short_introduction_to_channelz]
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_subchannel).

-behaviour(gen_statem).

%% Public API
-export([start_link/3,
         get_state/2,
         shutdown/2,
         start_rpc/2,
         wait_for_state_change/3]).

%% gen_statem callbacks
-export([callback_mode/0,
         init/1,
         handle_event/4]).

%% Types
-type from() :: {To :: pid(), Tag :: term()}.
-type state() :: idle | connecting | ready | transient_failure | shutdown.

%% Records
-record(data, {
    pool = nil :: nil | atom(),
    target = nil :: nil | grpcbox_target:t(),
    options = #{} :: map(),
    backoff = grpcbox_backoff:default() :: grpcbox_backoff:t(),
    connection_pid = nil :: nil | pid(),
    idle_timeout = timer:minutes(5) :: timeout(),
    start_connect_pid = nil :: nil | pid(),
    start_connect_tag = nil :: nil | reference(),
    start_rpc = [] :: [from()],
    wait_for_state_change = #{idle => [], connecting => [], ready => [], transient_failure => [], shutdown => []} :: #{state() := [from()]}
}).

%% Macros
-define(is_state(S), (S =:= connecting orelse S =:= ready orelse S =:= transient_failure orelse S =:= idle orelse S =:= shutdown)).
-define(is_timeout(T), ((is_integer(T) andalso T >= 0) orelse T =:= infinity)).

%%%===================================================================
%%% Public API functions
%%%===================================================================

start_link(Pool, Target=#{'__struct__' := grpcbox_target}, Options) ->
    gen_statem:start_link(?MODULE, {Pool, Target, Options}, []).

-spec get_state(pid(), boolean()) -> state().
get_state(Pid, TryToConnect) when is_boolean(TryToConnect) ->
    case erlang:is_process_alive(Pid) of
        true ->
            gen_statem:call(Pid, {get_state, TryToConnect});
        false ->
            shutdown
    end.

-spec shutdown(pid(), timeout()) -> ok.
shutdown(Pid, Timeout) when ?is_timeout(Timeout) ->
    case erlang:is_process_alive(Pid) of
        true ->
            MonitorRef = erlang:monitor(process, Pid),
            ok = gen_statem:cast(Pid, shutdown),
            receive
                {'DOWN', MonitorRef, process, Pid, _Reason} ->
                    ok
            after
                Timeout ->
                    _ = erlang:demonitor(MonitorRef, [flush]),
                    _ = erlang:exit(Pid, shutdown),
                    ok
            end;
        false ->
            ok
    end.

-spec start_rpc(pid(), timeout()) -> {ok, pid()} | {error, state()}.
start_rpc(Pid, Timeout) ->
    case erlang:is_process_alive(Pid) of
        true ->
            gen_statem:call(Pid, start_rpc);
        false ->
            {error, {badstate, shutdown}}
    end.

-spec wait_for_state_change(pid(), state(), timeout()) -> boolean().
wait_for_state_change(Pid, SourceState, Timeout) when ?is_state(SourceState) andalso ?is_timeout(Timeout) ->
    case erlang:is_process_alive(Pid) of
        true ->
            try gen_statem:call(Pid, {wait_for_state_change, SourceState}, Timeout)
            catch
                exit:{noproc, _} ->
                    (SourceState =:= shutdown);
                exit:{timeout, _} ->
                    false
            end;
        false when SourceState =:= shutdown ->
            true;
        false ->
            false
    end.

%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

callback_mode() ->
    [handle_event_function, state_enter].

init({Pool, Target, Options}) ->
    Data = #data{pool=Pool,
                 target=Target,
                 options=Options},
    {ok, connecting, Data}.

%% State Enter Events
% handle_event(enter, OldState, NewState, Data) ->
handle_event(enter, _OldState, NewState = connecting, Data0) ->
    Actions0 = [],
    {Data1, Actions1} = start_connect(Data0, Actions0),
    {Data2, Actions2} = reply_state_change(NewState, Data1, Actions1),
    io:format("connecting = ~p~n", [Actions2]),
    {keep_state, Data2, Actions2};
handle_event(enter, connecting, NewState = ready, Data0) ->
    Actions0 = [],
    {Data1, Actions1} = reply_state_change(NewState, Data0, Actions0),
    {Data2, Actions2} = reply_start_rpc(NewState, Data1, Actions1),
    {keep_state, Data2, Actions2};
handle_event(enter, _OldState, NewState = transient_failure, Data0) ->
    Actions0 = [],
    {Data1, Actions1} = reply_state_change(NewState, Data0, Actions0),
    {Data2, Actions2} = reply_start_rpc(NewState, Data1, Actions1),
    {Data3, Actions3} = backoff_transient_failure(Data2, Actions2),
    {keep_state, Data3, Actions3};
handle_event(enter, _OldState, NewState = idle, Data0=#data{start_rpc=[]}) ->
    Actions0 = [{{timeout, idle}, infinity, idle}],
    {Data1, Actions1} = reply_state_change(NewState, Data0, Actions0),
    {keep_state, Data1, Actions1};
handle_event(enter, _OldState, NewState = shutdown, Data0) ->
    Actions0 = [{{timeout, idle}, infinity, idle}],
    {Data1, Actions1} = reply_state_change(NewState, Data0, Actions0),
    {Data2, Actions2} = reply_start_rpc(NewState, Data1, Actions1),
    {keep_state, Data2, Actions2};
%% Generic Timeout Events
handle_event({timeout, idle}, idle, State, Data0=#data{start_rpc=S0}) when State =/= idle ->
    S1 = [From || From = {To, _Tag} <- S0, erlang:is_process_alive(To) =:= true],
    Data1 = Data0#data{start_rpc=S1},
    case S1 of
        [] ->
            Data2 = start_connect_exit(idle_timeout, Data1),
            {next_state, idle, Data2};
        [_ | _] ->
            Actions = reset_idle_timeout(Data1, []),
            {keep_state, Data1, Actions}
    end;
%% State Timeout Events
% handle_event(state_timeout, connect, connecting, Data0=#data{connection_pid=nil}) ->
%     case h2_client:start_link(Transport, Host, Port, options(Transport, SSLOptions)) of
%         {ok, ConnectionPid} ->
%             Data1 = Data0#data{connection_pid=ConnectionPid},
%             {next_state, ready, Data1};
%         Error = {error, _} ->
%             {Data1, Actions} = reply_start_rpc(Error, Data0, []),
%             {next_state, transient_failure, Data1, Actions}
%     end;
handle_event(state_timeout, connect_timeout, connecting, Data0) ->
    io:format("CONNECT TIMEOUT~n"),
    Data1 = start_connect_exit(connect_timeout, Data0),
    {Data2, Actions} = reply_start_rpc({error, connect_timeout}, Data1, []),
    {next_state, transient_failure, Data2, Actions};
handle_event(state_timeout, retry, transient_failure, Data) ->
    {next_state, connecting, Data};
%% Cast Events
handle_event(cast, shutdown, _State, Data) ->
    {next_state, shutdown, Data};
%% Call Events
handle_event({call, From}, start_rpc, ready, Data=#data{connection_pid=ConnectionPid}) when is_pid(ConnectionPid) ->
    Actions0 = [{reply, From, ConnectionPid}],
    Actions1 = reset_idle_timeout(Data, Actions0),
    {keep_state_and_data, Actions1};
handle_event({call, From}, start_rpc, State, Data0=#data{start_rpc=S0}) when (State =:= connecting orelse State =:= idle) ->
    S1 = [From | S0],
    Data1 = Data0#data{start_rpc=S1},
    Actions0 = [],
    Actions1 = reset_idle_timeout(Data1, Actions0),
    case State of
        connecting ->
            {keep_state, Data1, Actions1};
        idle ->
            {next_state, connecting, Data1, Actions1}
    end;
handle_event({call, From}, start_rpc, State, Data) when (State =:= transient_failure orelse State =:= shutdown) ->
    Actions0 = [{reply, From, {error, {badstate, State}}}],
    Actions1 = reset_idle_timeout(Data, Actions0),
    {keep_state_and_data, Actions1};
handle_event({call, From}, {get_state, TryToConnect}, State, Data) ->
    Actions = [{reply, From, State}],
    case TryToConnect of
        true ->
            try_to_connect(State, Data, Actions);
        false ->
            {keep_state_and_data, Actions}
    end;
handle_event({call, From}, {wait_for_state_change, State}, State, _Data) ->
    Actions = [{reply, From, true}],
    {keep_state_and_data, Actions};
handle_event({call, From}, {wait_for_state_change, NextState}, State, Data=#data{wait_for_state_change=W0}) ->
    W1 = maps:update_with(NextState, fun(Calls) -> [From | Calls] end),
    {keep_state, Data#data{wait_for_state_change=W1}};
%% Info Events
handle_event(info, {StartConnectTag, StartConnectResult}, connecting, Data0=#data{connection_pid=nil, start_connect_tag=StartConnectTag}) ->
    case StartConnectResult of
        {ok, ConnectionPid} when is_pid(ConnectionPid) ->
            true = link(ConnectionPid),
            Data1 = start_connect_exit(normal, Data0#data{connection_pid=ConnectionPid}),
            {next_state, ready, Data1};
        Error = {error, _} ->
            Data1 = start_connect_exit(normal, Data0),
            {Data2, Actions} = reply_start_rpc(Error, Data1, []),
            {next_state, transient_failure, Data2, Actions}
    end;
handle_event(info, {'EXIT', StartConnectPid, {Reason, Stacktrace}}, connecting, Data0=#data{connection_pid=nil, start_connect_tag=StartConnectTag}) ->
    erlang:raise(error, Reason, Stacktrace).

%% @private
backoff_connecting(Data0=#data{backoff=B0}, Actions0) ->
    {Timeout, B1} = grpcbox_backoff:connecting(B0),
    Data1 = Data0#data{backoff=B1},
    Actions1 = [{state_timeout, Timeout, connect_timeout} | Actions0],
    {Data1, Actions1}.

%% @private
backoff_ready(Data0=#data{backoff=B0}, Actions0) ->
    {_Timeout, B1} = grpcbox_backoff:ready(B0),
    Data1 = Data0#data{backoff=B1},
    {Data1, Actions0}.

%% @private
backoff_transient_failure(Data0=#data{backoff=B0}, Actions0) ->
    {Timeout, B1} = grpcbox_backoff:transient_failure(B0),
    Data1 = Data0#data{backoff=B1},
    Actions1 = [{state_timeout, Timeout, retry} | Actions0],
    {Data1, Actions1}.

%% @private
reply_start_rpc(_StateOrReply, Data=#data{start_rpc=[]}, Actions) ->
    {Data, Actions};
reply_start_rpc(StateOrReply, Data0=#data{connection_pid=ConnectionPid, start_rpc=Calls}, Actions0) ->
    Data1 = Data0#data{start_rpc=[]},
    Reply =
        case StateOrReply of
            {error, _} -> StateOrReply;
            ready -> {ok, ConnectionPid};
            _ when is_atom(StateOrReply) -> {error, {badstate, StateOrReply}}
        end,
    Actions1 = reply_to_all(Calls, Reply, Actions0),
    {Data1, Actions1}.

%% @private
reply_state_change(State, Data0=#data{wait_for_state_change=W0}, Actions0) ->
    case maps:get(State, W0) of
        [] ->
            {Data0, Actions0};
        Calls = [_ | _] ->
            W1 = maps:put(State, [], W0),
            Data1 = Data0#data{wait_for_state_change=W1},
            Actions1 = reply_to_all(Calls, true, Actions0),
            {Data1, Actions1}
    end.

%% @private
reply_to_all([From | Calls], Reply, Actions) ->
    reply_to_all(Calls, Reply, [{reply, From, Reply} | Actions]);
reply_to_all([], _Reply, Actions) ->
    Actions.

%% @private
reset_idle_timeout(#data{idle_timeout = IdleTimeout}, Actions) ->
    [{{timeout, idle}, IdleTimeout, idle} | Actions].

%% @private
start_connect(Data0=#data{start_connect_pid=nil, start_connect_tag=nil}, Actions0) ->
    StartConnectTag = erlang:make_ref(),
    {ok, StartConnectPid} = proc_lib:start_link(erlang, apply, [fun start_connect_init/3, [self(), StartConnectTag, Data0]]),
    Data1 = Data0#data{start_connect_pid=StartConnectPid, start_connect_tag=StartConnectTag},
    Actions1 = reset_idle_timeout(Data1, Actions0),
    {Data2, Actions2} = backoff_connecting(Data1, Actions1),
    {Data2, Actions2}.

%% @private
start_connect_init(Parent, Tag, _Data) ->
    ok = proc_lib:init_ack(Parent, {ok, self()}),
    % erlang:error(crash),
    % receive
    % after
    %     30000 ->
    %         ok
    % end,
    % Error = {error, unable_to_connect},
    % Parent ! {Tag, Error},
    % start_connect_loop(nil, Tag).
    case h2_client:start_link(Transport, Host, Port, options(Transport, SSLOptions)) of
        {ok, ConnectionPid} ->
            Parent ! {Tag, {ok, ConnectionPid}},
            start_connect_loop(ConnectionPid, Tag);
        Error = {error, _} ->
            Parent ! {Tag, Error},
            start_connect_loop(nil, Tag)
    end.

%% @private
start_connect_loop(ConnectionPid, Tag) ->
    receive
        {Tag, normal} when is_pid(ConnectionPid) ->
            true = unlink(ConnectionPid),
            exit(normal);
        {Tag, Reason} ->
            exit(Reason)
    end.

%% @private
start_connect_exit(_Reason, Data=#data{start_connect_pid=nil, start_connect_tag=nil}) ->
    Data;
start_connect_exit(Reason, Data0=#data{start_connect_pid=StartConnectPid, start_connect_tag=StartConnectTag}) when is_pid(StartConnectPid) andalso is_reference(StartConnectTag) ->
    StartConnectPid ! {StartConnectTag, Reason},
    ok =
        receive
            {'EXIT', StartConnectPid, Reason} ->
                ok
        after
            500 ->
                true = unlink(StartConnectPid),
                _ = erlang:exit(StartConnectPid, kill),
                receive
                    {'EXIT', StartConnectPid, _Reason} ->
                        ok
                after
                    0 ->
                        ok
                end
        end,
    Data1 = Data0#data{start_connect_pid=nil, start_connect_tag=nil},
    Data1.

%% @private
try_to_connect(shutdown, Data, Actions) ->
    {keep_state, Data, Actions};
try_to_connect(State, Data, Actions) when State =:= connecting orelse State =:= ready ->
    {keep_state, Data, reset_idle_timeout(Data, Actions)};
try_to_connect(State, Data, Actions) when State =:= idle orelse State =:= transient_failure ->
    {next_state, connecting, Data, Actions}.

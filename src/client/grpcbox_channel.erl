%%%-------------------------------------------------------------------
%% @doc grpcbox channel API
%% See [https://github.com/grpc/grpc/blob/master/doc/connectivity-semantics-and-api.md]
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_channel).

-behaviour(gen_statem).

-include("grpcbox.hrl").

%% Public API
-export([start_link/3,
         pick/1,
         stop/1]).

%% gen_statem callbacks
-export([callback_mode/0,
         init/1,
         handle_event/4,
         terminate/3]).

%% Types
-type t() :: atom().
-type transport() :: http | https.
-type host() :: inet:ip_address() | inet:hostname().
-type endpoint() :: {transport(), host(), inet:port_number(), ssl:ssl_option()}.
-type load_balancer() :: round_robin | random | hash | direct | claim | grpclb.
-type from() :: {To :: pid(), Tag :: term()}.
-type state() :: idle | connecting | ready | transient_failure | shutdown.

-type options() :: #{balancer => load_balancer(),
                     interceptor => module() | grpcbox_interceptor:t(),
                     message_accept_encoding => [grpcbox:encoding()],
                     message_encoding => gprcbox:encoding(),
                     resolver => module(),
                     transport => module()}.
                     % unary_interceptor => grpcbox_client:unary_interceptor(),
                     % stream_interceptor => grpcbox_client:stream_interceptor()}.
-export_type([t/0,
              options/0,
              endpoint/0]).

%% Records
-record(data, {pool = nil :: nil | atom(),
               balancer = round_robin :: load_balancer(),
               targets = [] :: [target()],
               interceptor = undefined :: undefined | grpcbox_interceptor:t(),
               message_accept_encoding = [identity] :: [grpcbox:encoding()],
               message_encoding = identity :: gprcbox:encoding(),
               resolver = grpcbox_name_resolver :: module(),
               user_agent = grpcbox:user_agent() :: binary()}).

% -record(data, {endpoints :: [endpoint()],
%                pool :: atom(),
%                resolver :: module(),
%                balancer :: grpcbox:balancer(),
%                encoding :: grpcbox:encoding(),
%                interceptors :: #{unary_interceptor => grpcbox_client:unary_interceptor(),
%                                  stream_interceptor => grpcbox_client:stream_interceptor()}
%                              | undefined,
%                stats_handler :: module() | undefined,
%                refresh_interval :: timer:time()}).

%% Macros
-define(DEFAULT_TIMEOUT, 5000).
-define(is_parent_channel(P), (P =:= root orelse (is_tuple(P) andalso tuple_size(P) =:= 2 andalso element(1, P) =:= channel))).
-define(is_timeout(T), ((is_integer(T) andalso T >= 0) orelse T =:= infinity)).

%%%===================================================================
%%% Public API functions
%%%===================================================================

%% @doc Create a top-level channel.
start_link(Name, Target = #{'__struct__' := grpcbox_target}, Options) when is_atom(Name) andalso is_map(Options) ->
    NameString = atom_to_binary(Name, unicode),
    gen_statem:start_link({local, Name}, ?MODULE, {root, NameString, Target, Options});
start_link(Name, Targets = [_ | _], Options) when is_atom(Name) andalso is_map(Options) ->
    NameString = atom_to_binary(Name, unicode),
    gen_statem:start_link({local, Name}, ?MODULE, {root, NameString, Targets, Options}).

%% @doc Create an internal channel.
start_link(Parent = {channel, _}, Name, Target = #{'__struct__' := grpcbox_target}, Options) when is_binary(Name) andalso is_map(Options) ->
    gen_statem:start_link(?MODULE, {Parent, Name, Target, Options}).

% start_link(Parent, Name, Target = #{'__struct__' := grpcbox_target}, Options) when ?is_parent_channel(Parent) andalso is_binary(Name) andalso is_map(Options) ->
%     gen_statem:start_link(?MODULE, {Parent, Name, Target, Options}, []).

-spec get_node_ctx(pid()) -> {ok, grpcbox_channelz:node_ctx()} | {error, term()}.
get_node_ctx(Pid) when is_pid(Pid) ->
    get_node_ctx(Pid, ?DEFAULT_TIMEOUT).

-spec get_node_ctx(pid(), timeout()) -> {ok, grpcbox_channelz:node_ctx()} | {error, term()}.
get_node_ctx(Pid, Timeout) when is_pid(Pid) andalso ?is_timeout(Timeout) ->
    try gen_statem:call(Pid, get_node_ctx)
    catch
        exit:{noproc, _} ->
            {error, noproc};
        exit:{timeout, _} ->
            {error, timeout}
    end.

-spec get_state(pid(), boolean()) -> state().
get_state(Pid, TryToConnect) when is_boolean(TryToConnect) ->
    case erlang:is_process_alive(Pid) of
        true ->
            gen_statem:call(Pid, {get_state, TryToConnect});
        false ->
            shutdown
    end.

% -spec shutdown(pid(), timeout()) -> ok.
% shutdown(Pid, Timeout) when ?is_timeout(Timeout) ->
%     case erlang:is_process_alive(Pid) of
%         true ->
%             MonitorRef = erlang:monitor(process, Pid),
%             ok = gen_statem:cast(Pid, shutdown),
%             receive
%                 {'DOWN', MonitorRef, process, Pid, _Reason} ->
%                     ok
%             after
%                 Timeout ->
%                     _ = erlang:demonitor(MonitorRef, [flush]),
%                     _ = erlang:exit(Pid, shutdown),
%                     ok
%             end;
%         false ->
%             ok
%     end.

% -spec start_rpc(pid(), timeout()) -> {ok, pid()} | {error, state()}.
% start_rpc(Pid, Timeout) ->
%     case erlang:is_process_alive(Pid) of
%         true ->
%             gen_statem:call(Pid, start_rpc);
%         false ->
%             {error, {badstate, shutdown}}
%     end.

% -spec wait_for_state_change(pid(), state(), timeout()) -> boolean().
% wait_for_state_change(Pid, SourceState, Timeout) when ?is_state(SourceState) andalso ?is_timeout(Timeout) ->
%     case erlang:is_process_alive(Pid) of
%         true ->
%             try gen_statem:call(Pid, {wait_for_state_change, SourceState}, Timeout)
%             catch
%                 exit:{noproc, _} ->
%                     (SourceState =:= shutdown);
%                 exit:{timeout, _} ->
%                     false
%             end;
%         false when SourceState =:= shutdown ->
%             true;
%         false ->
%             false
%     end.

% -spec start_link(atom(), [endpoint()], options()) -> {ok, pid()}.
% start_link(Name, Targets, Options) when is_atom(Name) ->
    % gen_statem:start_link({via, grpcbox_channelz, }).
    % gen_statem:start_link({local, Name}, ?MODULE, {Name, Targets, Options}, []).

% %% @doc Picks a subchannel from a pool using the configured strategy.
% -spec pick(t(), unary | stream) -> {ok, {pid(), grpcbox_client:interceptor() | undefined}} |
%                                    {error, undefined_channel}.
% pick(Name, CallType) ->
%     try {ok, {gproc_pool:pick_worker(Name), interceptor(Name, CallType)}}
%     catch
%         error:badarg ->
%             {error, undefined_channel}
%     end.

% -spec get_state(t(), boolean()) -> state().
% get_state(Name, TryToConnect) when is_boolean(TryToConnect) ->
%     case erlang:is_process_alive(Pid) of
%         true ->
%             gen_statem:call(Pid, {get_state, TryToConnect});
%         false ->
%             shutdown
%     end.

%% @doc Picks a subchannel from a pool using the configured strategy.
pick(Name) ->
    try {ok, {gproc_pool:pick_worker(Name), get_interceptor(Name)}}
    catch
        error:badarg ->
            {error, undefined_channel}
    end.

% -spec interceptor(t(), unary | stream) -> grpcbox_client:interceptor() | undefined.
% interceptor(Name, CallType) ->
%     case ets:lookup(?CHANNELS_TAB, {Name, CallType}) of
%         [] ->
%             undefined;
%         [{_, I}] ->
%             I
%     end.

stop(Name) ->
    gen_statem:stop(Name).

%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

callback_mode() ->
    [handle_event_function, state_enter].

init({Parent, Name, Target, Options0}) ->
    _ = erlang:process_flag(trap_exit, true),
    Defaults = #data{},
    {[Balancer,
      Interceptor,
      MessageAcceptEncoding,
      MessageEncoding,
      Resolver,
      Transport],
     Options1} = grpcbox_utils:take_options([{balancer, Defaults#data.balancer},
                                             {interceptor, Defaults#data.interceptor},
                                             {message_accept_encoding, Defaults#data.message_accept_encoding},
                                             {message_encoding, Defaults#data.message_encoding},
                                             {resolver, Defaults#data.resolver},
                                             {transport, Defaults#data.transport}], Options0),
    0 = map_size(Options1),
    case grpcbox_channelz:register_channel(Parent, Name, Target) of
        {ok, NodeCtx=#channelz_node_ctx{}} ->

        Error = {error, _Reason} ->
            {stop, Error}
    end.
    % Options2 = set_interceptor(Name, Options1),
    % 0 = map_size(Options2),
    PoolBalancer =
        case Balancer of
            grpclb -> round_robin;
            _ -> Balancer
        end,
    true = gproc_pool:new(Name, PoolBalancer, [{size, length(Targets)},
                                               {auto_size, true}]),
    Data = #data{pool=Name,
                 balancer=Balancer,
                 endpoints=Endpoints,
                 message_accept_encoding=MessageAcceptEncoding,
                 message_encoding=MessageEncoding,
                 transport=Transport},
    {ok, connecting, Data}.

%% State Enter Events
handle_event(enter, _OldState, connecting, _Data) ->
    Actions = [{state_timeout, 0, connect}],
    {keep_state_and_data, Actions};
%% State Timeout Events
handle_event(state_timeout, connect, connecting, Data) ->
    % Pool, Endpoint, #{ssl_options => SSLOptions, }
    [begin
         gproc_pool:add_worker(Pool, Endpoint),
         {ok, Pid} = grpcbox_subchannel:start_link(Endpoint, Pool, {Transport, Host, Port, SSLOptions},
                                                   Encoding, StatsHandler),
         Pid
     end || Endpoint={Transport, Host, Port, SSLOptions} <- Endpoints],
     ok;
%% Call Events
handle_event({call, From}, get_node_ctx, _State, Data)

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------
    
%% @private
get_interceptor(Name) ->
    case ets:lookup(?CHANNELS_TAB, Name) of
        [] ->
            undefined;
        [{Name, Interceptor}] ->
            Interceptor
    end.

%% @private
set_interceptor(Name, Options0) ->
    case take_option(interceptor, Options0, undefined) of
        {undefined, Options1} ->
            Options1;
        {Prototype, Options1} ->
            Interceptor = grpcbox_interceptor:new(Prototype),
            true = ets:insert(?CHANNELS_TAB, {Name, Interceptor}),
            Options1
    end.

%% @private
take_option(Key, Options0, Default) ->
    case maps:take(Key, Options0) of
        {Value, Options1} ->
            {Value, Options1};
        error ->
            {Default, Options0}
    end.

%% @private
take_options(Keys, Options) ->
    take_options(Keys, Options, []).

%% @private
take_options([{Key, Default} | Rest], Options0, Acc) ->
    {Value, Options1} = take_option(Key, Options0, Default),
    take_options(Rest, Options1, [Value | Acc]);
take_options([], Options, Acc) ->
    {lists:reverse(Acc), Options}.

init([Name, Endpoints, Options]) ->
    process_flag(trap_exit, true),

    BalancerType = maps:get(balancer, Options, round_robin),
    Encoding = maps:get(encoding, Options, identity),
    StatsHandler = maps:get(stats_handler, Options, undefined),

    insert_interceptors(Name, Options),

    gproc_pool:new(Name, BalancerType, [{size, length(Endpoints)},
                                        {autosize, true}]),
    {ok, idle, #data{pool=Name,
                     encoding=Encoding,
                     stats_handler=StatsHandler,
                     endpoints=Endpoints}, [{next_event, internal, connect}]}.

callback_mode() ->
    state_functions.

connected(EventType, EventContent, Data) ->
    handle_event(EventType, EventContent, Data).

idle(internal, connect, Data=#data{pool=Pool,
                                   stats_handler=StatsHandler,
                                   encoding=Encoding,
                                   endpoints=Endpoints}) ->
    [begin
         gproc_pool:add_worker(Pool, Endpoint),
         {ok, Pid} = grpcbox_subchannel:start_link(Endpoint, Pool, {Transport, Host, Port, SSLOptions},
                                                   Encoding, StatsHandler),
         Pid
     end || Endpoint={Transport, Host, Port, SSLOptions} <- Endpoints],
    {next_state, connected, Data};
idle({call, From}, pick, _Data) ->
    {keep_state_and_data, [{reply, From, {error, idle}}]};
idle(EventType, EventContent, Data) ->
    handle_event(EventType, EventContent, Data).

handle_event(_, _, Data) ->
    {keep_state, Data}.

terminate(_Reason, _State, #data{pool=Name}) ->
    gproc_pool:force_delete(Name),
    ok.

insert_interceptors(Name, Interceptors) ->
    insert_unary_interceptor(Name, Interceptors),
    insert_stream_interceptor(Name, stream_interceptor, Interceptors).

insert_unary_interceptor(Name, Interceptors) ->
    case maps:get(unary_interceptor, Interceptors, undefined) of
        undefined ->
            ok;
        {Interceptor, Arg} ->
            ets:insert(?CHANNELS_TAB, {{Name, unary}, Interceptor(Arg)});
        Interceptor ->
            ets:insert(?CHANNELS_TAB, {{Name, unary}, Interceptor})
    end.

insert_stream_interceptor(Name, _Type, Interceptors) ->
    case maps:get(stream_interceptor, Interceptors, undefined) of
        undefined ->
            ok;
        Interceptor0 ->
            Interceptor = grpcbox_client_stream_interceptor:new(Interceptor0),
            ets:insert(?CHANNELS_TAB, {{Name, stream}, Interceptor})
    end.

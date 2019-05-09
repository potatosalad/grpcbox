%%%-------------------------------------------------------------------
%% @doc grpcbox channel API
%% See [https://github.com/grpc/grpc/blob/master/doc/connectivity-semantics-and-api.md]
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_channel_simple).

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
-record(data, {pool = nil :: nil | term(),
               balancer = round_robin :: load_balancer(),
               target = grpcbox_target:t(),
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
-define(is_parent_channel(P), (P =:= root orelse (is_tuple(P) andalso tuple_size(P) =:= 2 andalso element(1, P) =:= channel))).

%%%===================================================================
%%% Public API functions
%%%===================================================================

% -spec start_link(atom(), [endpoint()], options()) -> {ok, pid()}.
start_link(Parent, Name, Target = #{'__struct__' := grpcbox_target}, Options) when ?is_parent_channel(Parent) andalso is_binary(Name) andalso is_map(Options) ->
    gen_statem:start_link(?MODULE, {Parent, Name, Target, Options}, []).
    % gen_statem:start_link({via, grpcbox_channelz, {register_channel, Parent, Name, Target}}, ?MODULE, {Parent, Name, Target, Options}).
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

% %% @doc Picks a subchannel from a pool using the configured strategy.
% pick(Name) ->
%     try {ok, {gproc_pool:pick_worker(Name), get_interceptor(Name)}}
%     catch
%         error:badarg ->
%             {error, undefined_channel}
%     end.

% % -spec interceptor(t(), unary | stream) -> grpcbox_client:interceptor() | undefined.
% % interceptor(Name, CallType) ->
% %     case ets:lookup(?CHANNELS_TAB, {Name, CallType}) of
% %         [] ->
% %             undefined;
% %         [{_, I}] ->
% %             I
% %     end.

% stop(Name) ->
%     gen_statem:stop(Name).

%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

callback_mode() ->
    [handle_event_function, state_enter].

init({Parent, Name, Target, Options}) ->
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
    Options2 = set_interceptor(Name, Options1),
    0 = map_size(Options2),
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
    case grpcbox_utils:take_option(interceptor, Options0, undefined) of
        {undefined, Options1} ->
            Options1;
        {Prototype, Options1} ->
            Interceptor = grpcbox_interceptor:new(Prototype),
            true = ets:insert(?CHANNELS_TAB, {Name, Interceptor}),
            Options1
    end.

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

-module(grpcbox_channelz).

-behaviour(gen_statem).

-export([start_link/0,
         next_id/0,
         register_channel/1,
         register_server/1,
         register_socket/1,
         register_subchannel/1]).

-export([callback_mode/0,
         init/1,
         handle_event/4]).

% -record(data, {

% }).

-record(channelz_node, {
    node_id = 0 :: non_neg_integer(),
    type = nil :: nil | atom(),
    name = <<>> :: binary(),
    state = 'UNKNOWN' :: atom(),
    target = <<>> :: binary(),
    calls_started = 0 :: non_neg_integer(),
    calls_failed = 0 :: non_neg_integer(),
    calls_succeeded = 0 :: non_neg_integer(),
    last_call_started = {0, 0} :: non_neg_integer(),
    num_events_logged = 0 :: non_neg_integer(),
    creation_timestamp = {0, 0} :: non_neg_integer(),
    max_events = 30 :: non_neg_integer(),
    events = queue:new() :: queue:queue(grpcbox_channelz_pb:channel_trace_event())
}).

-record(channelz_node_ctx, {
    node_id = 0 :: non_neg_integer(),
    type = nil :: nil | atom(),
    stats_enabled = false :: boolean(),
    trace_enabled = false :: boolean()
}).

%% Macros
-define(CHANNELZ_ID_TAB, grpcbox_channelz_id_tab).
-define(CHANNELZ_NODE_TAB, grpcbox_channelz_node_tab).
-define(MAX_ID, 16#ffffffffffffffff).
-define(MIN_ID, 16#0000000000000001).
% -define(is_id(Id), (is_integer(Id) andalso ?MIN_ID =< Id andalso Id =< ?MAX_ID)).

start_link() ->
    ok = maybe_init_ets(),
    gen_statem:start_link({local, ?MODULE}, ?MODULE, [], []).

get_top_channels(#{start_channel_id := StartChannelId, max_results := MaxResults}) ->
    MatchSpec = [{#channelz_node{node_id='$1', type=channel, _='_'}, [{'>', '$1', StartChannelId}], ['$_']}],
    case ets:select(?CHANNELZ_NODE_TAB, MatchSpec, MaxResults) of
        '$end_of_table' ->
            #{channel => [], 'end' => true};
        {Nodes, _Continuation} ->
            #{channel => [dump_node(Node) || Node <- Nodes], 'end' => false}
    end.
% % get_top_channels() ->
% %     ets:match_object(grpcbox_channelz, )

% % get_top_channels(Ctx, _GetTopChannelsRequest = #{start_channel_id := StartChannelId, max_results := MaxResults}) ->
% %     GetTopChannelsResponse = #{channel => [], 'end' => true},
% %     {ok, GetTopChannelsResponse, Ctx}.

% register_top_channel(Pid) when is_pid(Pid) ->
%     gen_statem:call(?MODULE, {register_top_channel, Pid}).

next_id() ->
    ets:update_counter(?CHANNELZ_ID_TAB, id, {2, 1, ?MAX_ID, ?MIN_ID}, {id, 0}).

% record_call_started(Id) when ?is_id(Id) ->
%     gen_statem:cast(?MODULE, {record_call_started, Id}).

% record_call_failed(Id) when ?is_id(Id) ->
%     gen_statem:cast(?MODULE, {record_call_failed, Id}).

% record_call_succeeded(Id) when ?is_id(Id) ->
%     gen_statem:cast(?MODULE, {record_call_succeeded, Id}).

add_trace_event(Severity, Description, NodeCtx=#channelz_node_ctx{stats_enabled=true, trace_enabled=true}) ->
    Event = #{description => Description,
              severity => coerce_severity(Severity),
              timestamp => google_protobuf_timestamp()},
    Update = fun(NodeData) -> push_event(NodeData, Event) end,
    lookup_and_replace(NodeCtx, Update);
add_trace_event(_Severity, _Description, _NodeCtx) ->
    true.

add_trace_event_with_reference(Severity, Description, Reference, NodeCtx=#channelz_node_ctx{stats_enabled=true, trace_enabled=true}) ->
    Event = #{description => Description,
              severity => coerce_severity(Severity),
              timestamp => google_protobuf_timestamp(),
              child_ref => Reference},
    Update = fun(NodeData) -> push_event(NodeData, Event) end,
    lookup_and_replace(NodeCtx, Update);
add_trace_event_with_reference(_Severity, _Description, _Reference, _NodeCtx) ->
    true.

set_state(_State, _NodeCtx=#channelz_node_ctx{stats_enabled=false}) ->
    true;
set_state(State, _NodeCtx=#channelz_node_ctx{node_id=NodeId, stats_enabled=true}) ->
    ets:update_element(?CHANNELZ_NODE_TAB, NodeId, {#channelz_node.state, coerce_state(State)}).

record_call_started(_NodeCtx=#channelz_node_ctx{stats_enabled=false}) ->
    0;
record_call_started(_NodeCtx=#channelz_node_ctx{node_id=NodeId, stats_enabled=true}) ->
    true = ets:update_element(?CHANNELZ_NODE_TAB, NodeId, {#channelz_node.last_call_started, timestamp()}),
    ets:update_counter(?CHANNELZ_NODE_TAB, NodeId, {#channelz_node.calls_started, 1}).

record_call_failed(_NodeCtx=#channelz_node_ctx{stats_enabled=false}) ->
    0;
record_call_failed(_NodeCtx=#channelz_node_ctx{node_id=NodeId, stats_enabled=true}) ->
    ets:update_counter(?CHANNELZ_NODE_TAB, NodeId, {#channelz_node.calls_failed, 1}).

record_call_succeeded(_NodeCtx=#channelz_node_ctx{stats_enabled=false}) ->
    0;
record_call_succeeded(_NodeCtx=#channelz_node_ctx{node_id=NodeId, stats_enabled=true}) ->
    ets:update_counter(?CHANNELZ_NODE_TAB, NodeId, {#channelz_node.calls_succeeded, 1}).

register_channel(Pid) when is_pid(Pid) ->
    gen_statem:call(?MODULE, {register_channel, next_id(), Pid}).

register_server(Pid) when is_pid(Pid) ->
    gen_statem:call(?MODULE, {register_server, next_id(), Pid}).

register_socket(Pid) when is_pid(Pid) ->
    gen_statem:call(?MODULE, {register_socket, next_id(), Pid}).

register_subchannel(Pid) when is_pid(Pid) ->
    gen_statem:call(?MODULE, {register_subchannel, next_id(), Pid}).

% init([]) ->
%     {ok, nil, nil}.

% handle_event({call, From}, )

%% @private
coerce_severity(V='CT_UNKNOWN') -> V;
coerce_severity(V='CT_INFO') -> V;
coerce_severity(V='CT_WARNING') -> V;
coerce_severity(V='CT_ERROR') -> V;
coerce_severity(unknown) -> 'CT_UNKNOWN';
coerce_severity(info) -> 'CT_INFO';
coerce_severity(warning) -> 'CT_WARNING';
coerce_severity(error) -> 'CT_ERROR'.

%% @private
coerce_state(V='UNKNOWN') -> V;
coerce_state(V='IDLE') -> V;
coerce_state(V='CONNECTING') -> V;
coerce_state(V='READY') -> V;
coerce_state(V='TRANSIENT_FAILURE') -> V;
coerce_state(V='SHUTDOWN') -> V;
coerce_state(unknown) -> 'UNKNOWN';
coerce_state(idle) -> 'IDLE';
coerce_state(connecting) -> 'CONNECTING';
coerce_state(ready) -> 'READY';
coerce_state(transient_failure) -> 'TRANSIENT_FAILURE';
coerce_state(shutdown) -> 'SHUTDOWN'.

%% @private
dump_node(#channelz_node{node_id=NodeId,
                         type=channel,
                         name=Name,
                         state=State,
                         target=Target,
                         calls_started=CallsStarted,
                         calls_failed=CallsFailed,
                         calls_succeeded=CallsSucceeded,
                         last_call_started=LastCallStarted,
                         num_events_logged=NumEventsLogged,
                         creation_timestamp=CreationTimestamp,
                         events=Events},
          #channelz_node_ctx{trace_enabled=TraceEnabled}) ->
    ChannelRef = #{channel_id => NodeId,
                   name => Name},
    ChannelData0 = #{state => State,
                     target => Target,
                     calls_started => CallsStarted,
                     calls_succeeded => CallsSucceeded,
                     calls_failed => CallsFailed,
                     last_call_started_timestamp => google_protobuf_timestamp(LastCallStarted)},
    ChannelData1 =
        case TraceEnabled of
            true ->
                ChannelData0#{trace => #{num_events_logged => NumEventsLogged,
                                         creation_timestamp => google_protobuf_timestamp(CreationTimestamp),
                                         events => queue:to_list(Events)}};
            false ->
                ChannelData0
        end,
    Channel = #{ref => ChannelRef,
                data => ChannelData%,
                % channel_ref => [],
                % subchannel_ref => [],
                % socket_ref => []
                },
    Channel.

%% @private
lookup_and_replace(#channelz_node_ctx{node_id=NodeId}, Update) when is_function(Update, 1) ->
    case ets:lookup(?CHANNELZ_NODE_TAB, NodeId) of
        [NodeData] ->
            1 =:= ets:select_replace(?CHANNELZ_NODE_TAB, [{NodeData, [], [{const, Update(NodeData)}]}]);
        _ ->
            false
    end.

%% @private
maybe_init_ets() ->
    case ets:info(?CHANNELZ_ID_TAB, name) of
        undefined ->
            ets:new(?CHANNELZ_ID_TAB, [ordered_set, named_table, public, {write_concurrency, true}]);
        _ ->
            ok
    end,
    case ets:info(?CHANNELZ_NODE_TAB, name) of
        undefined ->
            ets:new(?CHANNELZ_NODE_TAB, [ordered_set, named_table, public, {write_concurrency, true}, {keypos, #channelz_node.node_id}]);
        _ ->
            ok
    end,
    ok.

%% @private
push_event(NodeData=#channelz_node{num_events_logged=N, max_events=0}, _Event) ->
    NodeData#channelz_node{num_events_logged=N+1};
push_event(NodeData=#channelz_node{num_events_logged=N, max_events=MaxEvents, events=Events0}, Event) when is_integer(MaxEvents) andalso MaxEvents > 0 ->
    Events1 = maybe_drop_events(Events0, MaxEvents),
    Events2 = queue:in(Event, Events1),
    NodeData#channelz_node{num_events_logged=N+1, events=Events2}.

%% @private
maybe_drop_events(Events, MaxEvents) ->
    case queue:len(Events) of
        Length when Length >= MaxEvents ->
            maybe_drop_events(queue:drop(Events), MaxEvents);
        Length when Length < MaxEvents ->
            Events
    end.

%% @private
timestamp() ->
    {erlang:monotonic_time(), erlang:time_offset()}.

%% @private
google_protobuf_timestamp() ->
    google_protobuf_timestamp(timestamp()).

%% @private
google_protobuf_timestamp({Timestamp, Offset}) ->
    Native = Timestamp + Offset,
    Seconds = erlang:convert_time_unit(Native, native, second),
    Nanos = erlang:convert_time_unit(Native, native, nanosecond) - erlang:convert_time_unit(Seconds, second, nanosecond),
    #{seconds => Seconds, nanos => Nanos}.

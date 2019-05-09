-module(grpcbox_client_stream).

-behaviour(gen_statem).

%% Elixir API
-export(['__struct__'/0]).
-export(['__struct__'/1]).
-export([new/1]).
%% Public API
-export([cancel/1]).
-export([end_stream/1]).
-export([open/2]).
-export([send/2]).
-export([setopts/2]).
% %% Interceptor API
% -export([private_get/2]).
% -export([private_get/3]).
% -export([private_merge/2]).
% -export([private_put/3]).
% -export([private_remove/2]).
% -export([private_take/2]).
% -export([private_update/4]).
%% gen_statem callbacks
-export([callback_mode/0]).
-export([init/1]).
-export([handle_event/4]).

%% Records
-include("grpcbox.hrl").

-record(data, {
    parent = nil :: pid(),
    active = false :: boolean() | once,
    buffer = <<>> :: binary(),
    queue = queue:new() :: queue:queue(term()),
    stream = nil :: grpcbox_client:stream(),
    stream_id = nil :: non_neg_integer(),
    stream_pid = nil :: pid()
}).

%% Types
-type lifecycle() :: unary | stream.

-type options() :: map().

-type t() :: #{'__struct__' := ?MODULE,
               lifecycle := lifecycle(),
               transport := module(),
               ctx := ctx:t(),
               env := map(),
               channel := grpcbox_channel:t(),
               interceptor := grpcbox_client_interceptor:t() | undefined,
               method := binary(),
               definition := #grpcbox_def{},
               connection := pid(),
               encoding := grpcbox:encoding(),
               stats_handler := module() | undefined,
               stats_state := term(),
               stream_id := non_neg_integer(),
               stream_pid := pid(),
               state := atom(),
               status := nil | grpcbox_status:code(),
               message := nil | binary()}.

-export_type([lifecycle/0]).
-export_type([t/0]).

% %% Callbacks
% -callback stream_open(Stream, options()) -> {ok, Stream} | {error, term()} when Stream :: t().
% -callback stream_send_headers(Stream, Headers) -> {ok, Stream} when Stream :: t(), Headers :: grpcbox_metadata:t().
% -callback stream_recv_headers(Stream, Headers) -> {ok, Headers, Stream} when Stream :: t(), Headers :: grpcbox_metadata:t().
% -callback stream_encode_data(Stream, Message) -> {ok, Data, Stream} when Stream :: t(), Message :: term(), Data :: binary().
% -callback stream_decode_data(Stream, Data) -> {ok, Message, Stream} when Stream :: t(), Message :: term(), Data :: binary().
% -callback stream_encode_frame(Stream, Data) -> {ok, Frame, Stream} when Stream :: t(), Data :: binary(), Frame :: binary().
% -callback stream_decode_frame(Stream, Frame) -> {ok, Data, Rest, Stream} | {more, Rest, Stream} when Stream :: t(), Data :: binary(), Frame :: binary(), Rest :: binary().
% -callback stream_send_data(Stream, Message) -> {ok, Stream} when Stream :: t(), Message :: term().
% -callback stream_recv_data(Stream, Message) -> {ok, Message, Stream} when Stream :: t(), Message :: term().
% -callback stream_send_trailers(Stream, Trailers) -> {ok, Stream} when Stream :: t(), Trailers :: grpcbox_metadata:t().
% -callback stream_recv_trailers(Stream, Trailers) -> {ok, Trailers, Stream} when Stream :: t(), Trailers :: grpcbox_metadata:t().

% {grpc_headers, pid(), term()}
% {grpc_data, pid(), [term()]}
% {grpc_trailers, pid(), {grpc_status(), grpc_message(), term()}}
% {grpc_closed, pid()}
% {grpc_error, pid(), term()}

%%%===================================================================
%%% Elixir API functions
%%%===================================================================

'__struct__'() ->
    #{'__struct__' => ?MODULE,
      lifecycle => nil,
      transport => grpcbox_client_h2_stream,
      ctx => nil,
      env => #{},
      channel => nil,
      interceptor => nil,
      method => nil,
      definition => nil,
      connection => nil,
      encoding => nil,
      stream_id => nil,
      stream_pid => nil,
      state => init,
      status => nil,
      message => nil}.

'__struct__'(List) when is_list(List) ->
    '__struct__'(maps:from_list(List));
'__struct__'(Map) when is_map(Map) ->
    maps:fold(fun maps:update/3, '__struct__'(), Map).

new(Stream=#{'__struct__' := ?MODULE}) ->
    Stream;
new({Function, Arg}) when is_function(Function, 1) ->
    new(Function(Arg));
new(Map) when is_map(Map) ->
    '__struct__'(Map).

%%%===================================================================
%%% Public API functions
%%%===================================================================

cancel(Pid) ->
    case erlang:is_process_alive(Pid) of
        true ->
            gen_statem:call(Pid, cancel);
        false ->
            {error, closed}
    end.

end_stream(Pid) ->
    case erlang:is_process_alive(Pid) of
        true ->
            gen_statem:call(Pid, end_stream);
        false ->
            {error, closed}
    end.

open(Stream = #{'__struct__' := ?MODULE,
                state := init,
                stream_id := nil,
                stream_pid := nil}, Options) ->
    Active =
        case maps:get(active, Options, false) of
            A = true -> A;
            A = false -> A;
            A = once -> A
        end,
    gen_statem:start_link(?MODULE, {self(), Stream, Options, Active}, []).

send(Pid, Message) ->
    gen_statem:cast(Pid, {send, Message}).

setopts(Pid, []) ->
    case erlang:is_process_alive(Pid) of
        true ->
            ok;
        false ->
            {error, closed}
    end;
setopts(Pid, [Request = {active, A}]) when is_pid(Pid) andalso (is_boolean(A) orelse A =:= once) ->
    case erlang:is_process_alive(Pid) of
        true ->
            gen_statem:call(Pid, Request);
        false ->
            {error, closed}
    end.

%%%===================================================================
%%% Interceptor API functions
%%%===================================================================

% private_get(#{'__struct__' := ?MODULE,
%               private := Private}, Key) ->
%     maps:get(Key, Private).

% private_get(#{'__struct__' := ?MODULE,
%               private := Private}, Key, Default) ->
%     maps:get(Key, Private, Default).

% private_merge(S0=#{'__struct__' := ?MODULE,
%                    private := P0}, KeyValues) when is_map(KeyValues) ->
%     P1 = maps:merge(P0, KeyValues),
%     S0#{private := P1}.

% private_put(S0=#{'__struct__' := ?MODULE,
%                  private := Private}, Key, Value) ->
%     P1 = maps:put(Key, Value, P0),
%     S0#{private := P1}.

% private_remove(S0=#{'__struct__' := ?MODULE,
%                     private := P0}, Key) ->
%     case maps:is_key(Key, P0) of
%         true ->
%             P1 = maps:remove(Key, P0),
%             S0#{private := P1};
%         false ->
%             S0
%     end.

% private_take(S0=#{'__struct__' := ?MODULE,
%                   private := P0}, Key) ->
%     case maps:take(Key, P0) of
%         {V, P1} ->
%             {V, S0#{private := P1}};
%         error ->
%             error
%     end.

% private_update(S0=#{'__struct__' := ?MODULE,
%                     private := P0}, Key, Initial, UpdateFun) when is_function(UpdateFun, 1) ->
%     case maps:find(Key, P0) of
%         {ok, V0} ->
%             V1 = UpdateFun(V0),
%             P1 = maps:put(Key, V1, P0),
%             S0#{private := P1};
%         error ->
%             P1 = maps:put(Key, Initial, P0),
%             S0#{private := P1}
%     end.

% start_link(Ctx, Channel, Path, Input, Definition, Options) ->
%     Active =
%         case maps:get(active, Options, false) of
%             A = true -> A;
%             A = false -> A;
%             A = once -> A
%         end,
%     proc_lib:start_link(?MODULE, init_it, [self(), Ctx, Channel, Path, Input, Definition, Options, Active]).

%% @private
% init_it(Parent, Ctx, Channel, Path, Input, Definition, Options, Active) ->
% init_it(Parent, Stream, Options, Active) ->
%     _ = erlang:process_flag(trap_exit, true),
%     NextFun = fun grpcbox_client_h2_stream:stream_init/2,
%     case grpcbox_client_interceptor:stream_init(Stream, NextFun, Options) of
%       {ok, NewStream = #{stream_id := StreamId,
%                          stream_pid := StreamPid}} when is_pid(StreamPid) ->
%           ok = proc_lib:init_ack(Parent, {ok, self()}),
%           true = erlang:link(StreamPid),
%     % case grpcbox_client_stream:new_stream(Ctx, Channel, Path, Definition, Options) of
%     %     {ok, Stream = #{'__struct__' := grpcbox_client_stream, stream_id := StreamId, stream_pid := StreamPid}} ->
            
%     %         true = erlang:link(StreamPid),
%           Data = #data{
%               parent = Parent,
%               active = Active,
%               stream = NewStream,
%               stream_id = StreamId,
%               stream_pid = StreamPid
%           },
%           Actions = [],
%           gen_statem:enter_loop(?MODULE, [], open, Data, Actions);
%       Error = {error, _} ->
%           ok = proc_lib:init_ack(Parent, Error),
%           erlang:exit(normal)
%     end.

%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

callback_mode() ->
    [handle_event_function, state_enter].

init({Parent, Stream, Options, Active}) ->
    _ = erlang:process_flag(trap_exit, true),
    case grpcbox_client_interceptor:grpc_init(Stream#{state := connecting}, Options) of
        {ok, NewStream = #{state := ready,
                           stream_id := StreamId,
                           stream_pid := StreamPid}} when is_pid(StreamPid) ->
            true = erlang:link(StreamPid),
            Data = #data{
                parent = Parent,
                active = Active,
                stream = NewStream,
                stream_id = StreamId,
                stream_pid = StreamPid
            },
            Actions = [],
            {ok, open, Data, Actions};
        Error = {error, _} ->
            {stop, Error}
    end.

%% State Enter Events
handle_event(enter, open, open, _Data) ->
    keep_state_and_data;
handle_event(enter, open, State = closed, Data) ->
    maybe_stop(State, Data);
%% Cast Events
handle_event(cast, {send, Message}, open, Data0 = #data{stream = Stream0}) ->
    {ok, Stream1} = grpcbox_client_interceptor:grpc_send_data(Stream0, Message),
    Data1 = Data0#data{stream = Stream1},
    {keep_state, Data1};
handle_event(cast, {send, _Message}, closed, _Data) ->
    %% Ignore: we've already closed the stream.
    keep_state_and_data;
%% Call Events
handle_event({call, From}, {active, NewActive}, State, Data = #data{active = OldActive, queue = Queue}) ->
    Actions = [{reply, From, ok}],
    case {OldActive, NewActive} of
        {A, A} ->
            {keep_state_and_data, Actions};
        {false, once} ->
            NewData = forward_once(Data#data{active = once}, Queue),
            maybe_stop(State, NewData, Actions);
        {false, true} ->
            NewData = forward_active(Data#data{active = true}, Queue),
            maybe_stop(State, NewData, Actions);
        {_, A} when is_boolean(A) orelse A =:= once ->
            NewData = Data#data{active = NewActive},
            maybe_stop(State, NewData, Actions)
    end;
handle_event({call, From}, cancel, open, Data0 = #data{stream = Stream0}) ->
    {ok, Stream1} = grpcbox_client_interceptor:grpc_cancel(Stream0),
    Data1 = Data0#data{stream = Stream1},
    Actions = [{reply, From, ok}],
    {keep_state, Data1, Actions};
handle_event({call, From}, end_stream, open, Data0 = #data{stream = Stream0}) ->
    {ok, Stream1} = grpcbox_client_interceptor:grpc_end_stream(Stream0),
    Data1 = Data0#data{stream = Stream1},
    Actions = [{reply, From, ok}],
    {keep_state, Data1, Actions};
handle_event({call, From}, R, closed, _Data) when R =:= cancel orelse R =:= end_stream ->
    Actions = [{reply, From, {error, closed}}],
    {keep_state_and_data, Actions};
%% Info Events
handle_event(info, {grpc_headers, StreamId, Headers0}, open, Data0 = #data{stream = Stream0, stream_id = StreamId}) ->
    {ok, Headers1, Stream1} = grpcbox_client_interceptor:grpc_recv_headers(Stream0, Headers0),
    Data1 = Data0#data{stream = Stream1},
    NewData = maybe_forward(Data1, {grpc_headers, StreamId, Headers1}),
    {keep_state, NewData};
handle_event(info, {grpc_data, StreamId, MoreData}, open, Data = #data{stream = Stream, stream_id = StreamId, buffer = SoFar}) ->
    Buffer = <<SoFar/binary, MoreData/binary>>,
    do_recv_data(Stream, Buffer, Data, []);
handle_event(info, {grpc_trailers, StreamId, Trailers0}, open, Data0 = #data{stream = Stream0, stream_id = StreamId}) ->
    {ok, Trailers1, Stream1} = grpcbox_client_interceptor:grpc_recv_trailers(Stream0, Trailers0),
    Data1 = Data0#data{stream = Stream1},
    NewData = maybe_forward(Data1, {grpc_trailers, StreamId, Trailers1}),
    {keep_state, NewData};
handle_event(info, Message = {grpc_closed, StreamId}, open, Data = #data{stream_id = StreamId}) ->
    NewData = maybe_forward(Data, Message),
    {next_state, closed, NewData};
handle_event(info, {'END_STREAM', StreamId}, open, Data = #data{stream_id = StreamId}) ->
    NewData = maybe_forward(Data, {grpc_closed, StreamId}),
    {next_state, closed, NewData};
handle_event(info, {'EXIT', StreamPid, Reason}, open, Data = #data{stream_pid = StreamPid}) ->
    NewData = maybe_forward(Data, {'EXIT', StreamPid, Reason}),
    {next_state, closed, NewData};
handle_event(info, {grpc_closed, StreamId}, closed, _Data = #data{stream_id = StreamId}) ->
    %% Ignore: we've already closed the stream.
    keep_state_and_data;
handle_event(info, {'END_STREAM', StreamId}, closed, _Data = #data{stream_id = StreamId}) ->
    %% Ignore: we've already closed the stream.
    keep_state_and_data;
handle_event(info, {'EXIT', StreamPid, _Reason}, closed, _Data = #data{stream_pid = StreamPid}) ->
    %% Ignore: we've already closed the stream.
    keep_state_and_data;
handle_event(info, {'PONG', _}, _State, _Data) ->
    %% Ignore: h2_connection can potentially send this.
    keep_state_and_data.
% handle_event(info, {'EXIT', Parent, _Reason}, _State, _Data = #data{parent = Parent, stream = Stream}) ->
%     % Parent has exited. Close the stream and shutdown.
%     ok = grpcbox_client:close_send(Stream),
%     stop.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @private
do_recv_data(Stream0, Buffer, Data, Acc) ->
    case grpcbox_client_interceptor:grpc_recv_data(Stream0, Buffer) of
        {ok, Message, Rest, Stream1} ->
            do_recv_data(Stream1, Rest, Data, [Message | Acc]);
        {more, Rest, Stream1} when Acc =:= [] ->
            NewData = Data#data{stream = Stream1, buffer = Rest},
            {keep_state, NewData};
        {more, Rest, Stream1} ->
            NewData = maybe_forward(Data#data{stream = Stream1, buffer = Rest}, {grpc_data, 1, lists:reverse(Acc)}),
            {keep_state, NewData}
    end.

%% @private
forward(#data{parent = Parent}, RawMessage) ->
    Message =
        case RawMessage of
            {grpc_headers, _, Headers} -> {grpc_headers, self(), Headers};
            {grpc_data, Data} when is_list(Data) -> {grpc_data, self(), Data};
            {grpc_data, _, Data} -> {grpc_data, self(), [Data]};
            {grpc_trailers, _, Trailers} -> {grpc_trailers, self(), Trailers};
            {grpc_closed, _} -> {grpc_closed, self()};
            {'EXIT', _, _} -> {grpc_error, self(), RawMessage}
        end,
    catch Parent ! Message,
    ok.

%% @private
forward_active(Data = #data{active = true}, Queue) ->
    case queue:out(Queue) of
        {{value, {grpc_data, _, Message}}, NewQueue} ->
            forward_active(Data, forward_data(Data, NewQueue, [Message]));
        {{value, Message}, NewQueue} ->
            ok = forward(Data, Message),
            forward_active(Data, NewQueue);
        {empty, Queue} ->
            Data#data{queue = Queue}
    end.

%% @private
forward_data(Data, Queue, Acc) ->
    case queue:out(Queue) of
        {{value, {grpc_data, _, Message}}, NewQueue} ->
            forward_data(Data, NewQueue, [Message | Acc]);
        {{value, _}, _} ->
            ok = forward(Data, {grpc_data, lists:reverse(Acc)}),
            Queue;
        {empty, Queue} ->
            ok = forward(Data, {grpc_data, lists:reverse(Acc)}),
            Queue
    end.

%% @private
forward_once(Data = #data{active = once}, Queue) ->
    case queue:out(Queue) of
        {{value, {grpc_data, _, Message}}, NewQueue} ->
            Data#data{active = false, queue = forward_data(Data, NewQueue, [Message])};
        {{value, Message}, NewQueue} ->
            ok = forward(Data, Message),
            Data#data{active = false, queue = NewQueue};
        {empty, Queue} ->
            Data#data{queue = Queue}
    end.

%% @private
maybe_forward(Data = #data{active = false, queue = Queue}, Message) ->
    NewQueue = queue:in(Message, Queue),
    Data#data{queue = NewQueue};
maybe_forward(Data = #data{active = once}, Message) ->
    ok = forward(Data, Message),
    Data#data{active = false};
maybe_forward(Data = #data{active = true}, Message) ->
    ok = forward(Data, Message),
    Data.

%% @private
maybe_stop(State, Data) ->
    maybe_stop(State, Data, []).

%% @private
maybe_stop(open, Data, Actions) ->
    {keep_state, Data, Actions};
maybe_stop(closed, Data = #data{queue = Queue}, Actions) ->
    case queue:is_empty(Queue) of
        true when Actions == [] ->
            {stop, normal, Data};
        true ->
            {stop_and_reply, normal, Data, Actions};
        false ->
            {keep_state, Data}
    end.

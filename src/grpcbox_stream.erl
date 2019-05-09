-module(grpcbox_stream).

-export(['__struct__'/0,
         '__struct__'/1]).

-export([accept_stream/2,
         init_stream/2,
         new_client/1,
         new_server/1]).

-export([callback_mode/0,
         init/1,
         handle_event/4]).

-type kind() :: client | server.

-type t() :: #{'__struct__' := ?MODULE,
               kind := kind(),
               transport := module(),
               ctx := ctx:t(),
               env := map(),
               channel := nil | grpcbox_channel:t(),
               interceptor := grpcbox_interceptor:t() | undefined,
               method := binary(),
               connection_pid := nil | pid(),
               definition := nil | #grpcbox_def{},
               owner_pid := nil | pid(),
               stream_id := nil | non_neg_integer(),
               stream_pid := nil | pid(),
               transport_pid := nil | pid(),
               recv_encoding := nil | grpcbox:encoding(),
               recv_initial_metadata := boolean(),
               recv_message_id := pos_integer(),
               recv_trailing_metadata := boolean(),
               sent_encoding := nil | grpcbox:encoding(),
               sent_initial_metadata := boolean(),
               sent_message_id := pos_integer(),
               sent_trailing_metadata := boolean(),
               status := nil | grpcbox_status:code(),
               message := nil | binary()}.

%% Records
% -record(outbox, {
%     initial = false :: {true, term()} | boolean(),
%     message = false :: {true, [term()]} | boolean(),
%     trailer = false :: {true, queue:queue(term())} | boolean()
% }).

-record(data, {
    parent = nil :: nil | pid(),
    stream = nil :: nil | t(),
    active = false :: boolean() | once,
    buffer = <<>> :: binary(),
    % recv_initial_metadata = false :: boolean(),
    % recv_trailing_metadata = false :: boolean(),
    queue = queue:new()
    % queue = queue:new() :: queue:queue({atom(), term()})
    % queue = {false, [], []} :: {boolean() | term(), [term()], [term()]}
    % outbox = #outbox{} :: #outbox{}
    % kind = nil :: nil | client | server,
    % connection_pid = nil :: nil | pid(),
    % owner_pid = nil :: nil | pid(),
    % stream = nil :: nil | t(),
    % stream_id = nil :: nil | non_neg_integer(),
    % stream_pid = nil :: nil | pid(),
}).

%%%===================================================================
%%% Elixir API functions
%%%===================================================================

'__struct__'() ->
    #{'__struct__' => ?MODULE,
      kind => nil,
      transport => nil,
      ctx => nil,
      env => nil,
      channel => nil,
      interceptor => nil,
      method => nil,
      definition => nil,
      connection_pid => nil,
      owner_pid => nil,
      stream_id => nil,
      stream_pid => nil,
      transport_pid => nil,
      recv_encoding => nil,
      recv_initial_metadata => false,
      recv_message_id => 1,
      recv_trailing_metadata => false,
      sent_encoding => nil,
      sent_initial_metadata => false,
      sent_message_id => 1,
      sent_trailing_metadata => false,
      status => nil,
      message => nil}.

'__struct__'(List) when is_list(List) ->
    '__struct__'(maps:from_list(List));
'__struct__'(Map) when is_map(Map) ->
    maps:fold(fun maps:update/3, '__struct__'(), Map).

% new(Stream=#{'__struct__' := ?MODULE}) ->
%     Stream;
% new({Function, Arg}) when is_function(Function, 1) ->
%     new(Function(Arg));
% new(Map) when is_map(Map) ->
%     '__struct__'(Map).

%%%===================================================================
%%% Public API functions
%%%===================================================================

accept_stream(Stream=#{kind := server}, Options) ->
    gen_statem:start_link(?MODULE, {self(), Stream, Options}, []).

init_stream(Stream=#{kind := client}, Options) ->
    gen_statem:start_link(?MODULE, {self(), Stream, Options}, []).

new_client(Stream=#{'__struct__' := ?MODULE, kind := client}) ->
    Stream;
new_client({Function, Arg}) when is_function(Function, 1) ->
    new_client(Function(Arg));
new_client(Map) when is_map(Map) ->
    '__struct__'(Map).

new_server(Stream=#{'__struct__' := ?MODULE, kind := server}) ->
    Stream;
new_server({Function, Arg}) when is_function(Function, 1) ->
    new_server(Function(Arg));
new_server(Map) when is_map(Map) ->
    '__struct__'(Map).

%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

callback_mode() ->
    [handle_event_function, state_enter].

init({Parent, Stream0=#{kind := client, owner_pid := nil}, Options}) ->
    _ = erlang:process_flag(trap_exit, true),
    case grpcbox_transport:init_stream(Stream0#{owner_pid := Parent}, Options) of
        {ok, Stream1=#{connection_pid := ConnectionPid,
                       stream_pid := StreamPid}} when is_pid(ConnectionPid) andalso is_pid(StreamPid) ->
            true = erlang:link(ConnectionPid),
            true = erlang:link(StreamPid),
            Data = #data{parent=Parent,
                         active=true,
                         stream=Stream1},
            Actions = [],
            {ok, connected, Data, Actions};
        Error = {error, _} ->
            {stop, Error}
    end;
init({Parent, Stream0=#{kind := server}, Options}) ->
    _ = erlang:process_flag(trap_exit, true),
    case grpcbox_transport:accept_stream(Stream0, Options) of
        {ok, Stream1=#{connection_pid := ConnectionPid,
                       stream_pid := StreamPid}} when is_pid(ConnectionPid) andalso is_pid(StreamPid) ->
            true = erlang:link(ConnectionPid),
            true = erlang:link(StreamPid),
            Data = #data{parent=Parent,
                         active=true,
                         stream=Stream1},
            Actions = [],
            {ok, connected, Data, Actions};
        Error = {error, _} ->
            {stop, Error}
    end.

%% State Enter Events
handle_event(enter, _OldState, _NewState, _Data) ->
    keep_state_and_data;
%% Info Events
handle_event(info, {'$grpc_initial_metadata', StreamId, Metadata0}, connected, Data0=#data{stream=Stream0=#{stream_id := StreamId, recv_initial_metadata := false}}) ->
    case grpcbox_transport:recv_initial_metadata(Stream0, Metadata0) of
        {ok, Metadata1, Stream1} ->
            Data1 = Data0#data{stream=Stream1},
            Data2 = maybe_output(Data1, {grpc_initial_metadata, self(), Metadata1}),
            {keep_state, Data2}
    end;
handle_event(info, {'$grpc_data', StreamId, MoreData}, connected, Data=#data{stream=Stream=#{stream_id := StreamId, recv_trailing_metadata := false}, buffer=SoFar}) ->
    Buffer = <<SoFar/binary, MoreData/binary>>,
    handle_grpc_data(Stream, Buffer, Data, []);
handle_event(info, {'$grpc_trailing_metadata', StreamId, Metadata0}, connected, Data0=#data{stream=Stream0=#{stream_id := StreamId, recv_trailing_metadata := false}}) ->
    case grpcbox_transport:recv_trailing_metadata(Stream0, Metadata0) of
        {ok, Metadata1, Stream1} ->
            Data1 = Data0#data{stream=Stream1},
            Data2 = maybe_output(Data1, {grpc_trailing_metadata, self(), Metadata1}),
            {keep_state, Data2}
    end.
% handle_event(info, Info, _State, Data0=#data{stream=Stream0}) ->
%   case grpcbox_transport:handle_info(Stream0, Info) of
%       {ok, Stream1} ->

% handle_event(info, {grpc_headers, StreamId, Headers0}, open, Data0 = #data{stream = Stream0, stream_id = StreamId}) ->
%     {ok, Headers1, Stream1} = grpcbox_client_interceptor:grpc_recv_headers(Stream0, Headers0),
%     Data1 = Data0#data{stream = Stream1},
%     NewData = maybe_forward(Data1, {grpc_headers, StreamId, Headers1}),
%     {keep_state, NewData};
% handle_event(info, {grpc_data, StreamId, MoreData}, open, Data = #data{stream = Stream, stream_id = StreamId, buffer = SoFar}) ->
%     Buffer = <<SoFar/binary, MoreData/binary>>,
%     do_recv_data(Stream, Buffer, Data, []);
% handle_event(info, {grpc_trailers, StreamId, Trailers0}, open, Data0 = #data{stream = Stream0, stream_id = StreamId}) ->
%     {ok, Trailers1, Stream1} = grpcbox_client_interceptor:grpc_recv_trailers(Stream0, Trailers0),
%     Data1 = Data0#data{stream = Stream1},
%     NewData = maybe_forward(Data1, {grpc_trailers, StreamId, Trailers1}),
%     {keep_state, NewData};

%% @private
handle_grpc_data(Stream0, Buffer, Data0, Acc) ->
    case grpcbox_transport:recv_message(Stream0, Buffer) of
        {ok, Message, Rest, Stream1} ->
            handle_grpc_data(Stream1, Rest, Data0, [Message | Acc]);
        {more, Rest, Stream1} when Acc =:= [] ->
            Data1 = Data0#data{stream=Stream1,
                               buffer=Rest},
            {keep_state, Data1};
        {more, Rest, Stream1} ->
            Data1 = Data0#data{stream=Stream1,
                               buffer=Rest},
            Data2 = maybe_output(Data1, {grpc_messages, self(), lists:reverse(Acc)}),
            {keep_state, Data2}
    end.

%% @private
maybe_output(Data=#data{active=true}, Message) ->
    ok = output(Data, Message),
    Data;
maybe_output(Data=#data{active=once}, Message) ->
    ok = output(Data, Message),
    Data#data{active=false};
maybe_output(Data=#data{active=false, queue=Queue}, Message) ->
    Data#data{queue=queue:in(Message, Queue)}.

%% @private
output(#data{stream=#{owner_pid := OwnerPid}}, Message) when is_pid(OwnerPid) ->
    catch OwnerPid ! Message,
    ok.

% maybe_output(Data=#data{active=true, outbox=Outbox=#outbox{initial=false, message=false, trailer=false}, stream=#{owner_pid := OwnerPid}}, {grpc_initial_metadata, Metadata}) when is_pid(OwnerPid) ->
%     OwnerPid ! {grpc_initial_metadata, self(), Metadata},
%     Data#data{outbox=Outbox#outbox{initial=true}};
% maybe_output(Data=#data{active=once, outbox=Outbox=#outbox{initial=false, message=false, trailer=false}, stream=#{owner_pid := OwnerPid}}, {grpc_initial_metadata, Metadata}) when is_pid(OwnerPid) ->
%     OwnerPid ! {grpc_initial_metadata, self(), Metadata},
%     Data#data{active=false, outbox=Outbox#outbox{initial=true}};
% maybe_output(Data=#data{active=false, outbox=Outbox=#outbox{initial=false, message=false, trailer=false}}, Item = {grpc_initial_metadata, _Metadata}) ->
%     Data#data{outbox=Outbox#outbox{initial={true, Item}}};
% maybe_output(Data=#data{active=true, outbox=Outbox=#outbox{initial=true, message=false, trailer=false}, stream=#{owner_pid := OwnerPid}}, {grpc_messages, Message}) when is_pid(OwnerPid) ->
%     OwnerPid ! {grpc_messages, self(), Metadata},
%     Data#data{outbox=Outbox#outbox{initial=true}};
% maybe_output(Data=#data{active=once, outbox=Outbox=#outbox{initial=true, message=false, trailer=false}, stream=#{owner_pid := OwnerPid}}, {grpc_messages, Message}) when is_pid(OwnerPid) ->
%     OwnerPid ! {grpc_messages, self(), Message},
%     Data#data{active=false, outbox=Outbox#outbox{initial=true}};
% maybe_output(Data=#data{active=false, outbox=Outbox=#outbox{initial=true, message=false, trailer=false}}, Item = {grpc_messages, _Message}) ->
%     Data#data{outbox=Outbox#outbox{initial={true, Item}}};

% %% @private
% maybe_output_head(Data=#data{active=false, hqueue=Queue}, Message) ->
%     Data#data{hqueue=[Message | Queue]}.

% maybe_output_head(Data=#data{active=true, hqueue=false, stream=#{owner_pid := OwnerPid}}, Message) when is_pid(OwnerPid) ->
%     OwnerPid ! {grpc_initial_metadata, self(), [Message]},
%     Data;
% maybe_output_head(Data=#data{active=once, dqueue=[], stream=#{owner_pid := OwnerPid}}, Message) when is_pid(OwnerPid) ->
%     OwnerPid ! {grpc_messages, self(), [Message]},
%     Data#data{active=false};
% maybe_output_head(Data=#data{active=false, dqueue=Queue}, Message) ->
%     Data#data{dqueue=[Message | Queue]}.

% %% @private
% maybe_output_data(Data=#data{active=true, dqueue=[], stream=#{owner_pid := OwnerPid}}, Message) when is_pid(OwnerPid) ->
%     OwnerPid ! {grpc_messages, self(), [Message]},
%     Data;
% maybe_output_data(Data=#data{active=once, dqueue=[], stream=#{owner_pid := OwnerPid}}, Message) when is_pid(OwnerPid) ->
%     OwnerPid ! {grpc_messages, self(), [Message]},
%     Data#data{active=false};
% maybe_output_data(Data=#data{active=false, dqueue=Queue}, Message) ->
%     Data#data{dqueue=[Message | Queue]}.

% %% @private
% maybe_output_tail(Data=#data{active=false, tqueue=Queue}, Message) ->
%     Data#data{tqueue=[Message | Queue]}.

%% @private
% maybe_output_message(Data0=#data{outbox=#outbox{initial=[], message=[], trailer=[]}, stream=})

-module(grpcbox_h2_stream).

-behaviour(h2_stream).

%% h2_stream callbacks
-export([init/3,
         on_receive_headers/2,
         on_send_push_promise/2,
         on_receive_data/2,
         on_end_stream/1,
         handle_info/2]).

-include("grpcbox.hrl").
-include_lib("chatterbox/include/http2.hrl").

-record(state, {
    kind = nil :: nil | client | server,
    connection_pid = nil :: nil | pid(),
    stream_id = nil :: nil | pos_integer(),
    transport_pid = nil :: nil | pid(),
    socket = nil :: nil | term(),
    recv_initial_metadata = false :: boolean(),
    recv_trailing_metadata = false :: boolean()
}).

%% h2_stream callbacks

% % init(ConnPid, StreamId, [Socket, ServicesTable, AuthFun, UnaryInterceptor,
% %                          StreamInterceptor, StatsHandler]) ->
% %     process_flag(trap_exit, true),
% %     State = #state{connection_pid=ConnPid,
% %                    stream_id=StreamId,
% %                    services_table=ServicesTable,
% %                    buffer = <<>>,
% %                    auth_fun=AuthFun,
% %                    unary_interceptor=UnaryInterceptor,
% %                    stream_interceptor=StreamInterceptor,
% %                    socket=Socket,
% %                    handler=self(),
% %                    stats_handler=StatsHandler},
% %     {ok, State}.

init(ConnectionPid, StreamId, [Socket, _Stream=#{kind := client,
                                                 connection_pid := nil,
                                                 stream_id := nil,
                                                 stream_pid := nil,
                                                 transport_pid := TransportPid}]) when is_pid(TransportPid) ->
    _ = erlang:process_flag(trap_exit, true),
    State = #state{kind=client,
                   connection_pid=ConnectionPid,
                   stream_id=StreamId,
                   transport_pid=TransportPid,
                   socket=Socket},
    {ok, State};
init(ConnectionPid, StreamId, [Socket, Stream0=#{kind := server,
                                                 connection_pid := nil,
                                                 stream_id := nil,
                                                 stream_pid := nil,
                                                 transport_pid := nil}, Options]) ->
    _ = erlang:process_flag(trap_exit, true),
    Stream1 = Stream0#{connection_pid := ConnectionPid,
                       stream_id := StreamId,
                       stream_pid := self()},
    {ok, TransportPid} = grpcbox_stream:accept_stream(Stream1, Options),
    State = #state{kind=server,
                   connection_pid=ConnectionPid,
                   stream_id=StreamId,
                   transport_pid=TransportPid,
                   socket=Socket},
    {ok, State}.

on_receive_headers(Headers, State0=#state{kind=server, stream_id=StreamId, transport_pid=Pid, recv_initial_metadata=false}) ->
    Pid ! {'$grpc_initial_metadata', StreamId, Headers},
    State1 = State0#state{recv_initial_metadata=true},
    {ok, State1};
on_receive_headers(Headers, State0=#state{kind=client, stream_id=StreamId, transport_pid=Pid, recv_initial_metadata=false}) ->
    Pid ! {'$grpc_initial_metadata', StreamId, Headers},
    State1 = State0#state{recv_initial_metadata=true},
    %% TODO: better way to know if it is a Trailers-Only response?
    %% maybe chatterbox should include information about the end of the stream
    case lists:keyfind(<<"grpc-status">>, 1, Headers) of
        false ->
            {ok, State1};
        {<<"grpc-status">>, _Status} ->
            Pid ! {'$grpc_trailing_metadata', StreamId, Headers},
            State2 = State1#state{recv_trailing_metadata=true},
            {ok, State2}
    end;
on_receive_headers(Headers, State0=#state{kind=client, stream_id=StreamId, transport_pid=Pid, recv_trailing_metadata=false}) ->
    Pid ! {'$grpc_trailing_metadata', StreamId, Headers},
    State1 = State0#state{recv_trailing_metadata=true},
    {ok, State1}.

on_send_push_promise(_Headers, State) ->
    %% Ignored.
    {ok, State}.

on_receive_data(Data, State=#state{stream_id=StreamId, transport_pid=Pid, recv_initial_metadata=true, recv_trailing_metadata=false}) ->
    Pid ! {'$grpc_data', StreamId, Data},
    {ok, State}.

on_end_stream(unreachable) ->
    erlang:error(unreachable).

% on_end_stream(State=#state{stream_id = StreamId, client_pid = Pid}) ->
%     Pid ! {grpc_end_stream, StreamId},
%     {ok, State}.

handle_info(unreachable, unreachable) ->
    erlang:error(unreachable).

% % on_receive_headers(Headers, State=#state{ctx=_Ctx}) ->
% %     %% proplists:get_value(<<":method">>, Headers) =:= <<"POST">>,
% %     Metadata = grpcbox_utils:headers_to_metadata(Headers),
% %     Ctx = case parse_options(<<"grpc-timeout">>, Headers) of
% %               infinity ->
% %                   grpcbox_metadata:new_incoming_ctx(Metadata);
% %               D ->
% %                   ctx:with_deadline_after(grpcbox_metadata:new_incoming_ctx(Metadata), D, nanosecond)
% %           end,

% %     FullPath = proplists:get_value(<<":path">>, Headers),
% %     %% wait to rpc_begin here since we need to know the method
% %     Ctx1 = ctx:with_value(Ctx, grpc_server_method, FullPath),
% %     State1=#state{ctx=Ctx2} = stats_handler(Ctx1, rpc_begin, {}, State#state{full_method=FullPath}),

% %     RequestEncoding = parse_options(<<"grpc-encoding">>, Headers),
% %     ResponseEncoding = parse_options(<<"grpc-accept-encoding">>, Headers),
% %     ContentType = parse_options(<<"content-type">>, Headers),

% %     RespHeaders = [{<<":status">>, <<"200">>},
% %                    {<<"user-agent">>, grpcbox:user_agent()},
% %                    {<<"content-type">>, content_type(ContentType)}
% %                    | response_encoding(ResponseEncoding)],

% %     handle_service_lookup(Ctx2, string:lexemes(FullPath, "/"),
% %                           State1#state{resp_headers=RespHeaders,
% %                                        req_headers=Headers,
% %                                        request_encoding=RequestEncoding,
% %                                        response_encoding=ResponseEncoding,
% %                                        content_type=ContentType}).

% on_receive_headers(H, State0=#state{resp_trailers = false, stream_id = StreamId, client_pid = Pid}) ->
%     Pid ! {grpc_headers, StreamId, H},
%     State1 = State0#state{resp_trailers = true},
%     %% TODO: better way to know if it is a Trailers-Only response?
%     %% maybe chatterbox should include information about the end of the stream
%     case proplists:get_value(<<"grpc-status">>, H, undefined) of
%         undefined ->
%             {ok, State1};
%         _Status ->
%             Pid ! {grpc_trailers, StreamId, H},
%             {ok, State1}
%     end;
% on_receive_headers(H, State=#state{resp_trailers = true, stream_id = StreamId, client_pid = Pid}) ->
%     Pid ! {grpc_trailers, StreamId, H},
%     {ok, State}.

% on_send_push_promise(_Headers, State) ->
%     {ok, State}.

% on_receive_data(Data, State=#state{stream_id = StreamId, client_pid = Pid}) ->
%     Pid ! {grpc_data, StreamId, Data},
%     {ok, State}.

% on_end_stream(State=#state{stream_id = StreamId, client_pid = Pid}) ->
%     Pid ! {grpc_closed, StreamId},
%     {ok, State}.

% handle_info(_Info, State) ->
%     io:format("GOT INFO ~p~n", [_Info]),
%     State.

%%

% %% @private
% recv_(Pid, MonitorRef, StreamId, Timeout) ->
%     receive
%         {grpc_headers, StreamId, Headers} ->
%             {ok, {headers, Headers}};
%         {grpc_data, StreamId, Data} ->
%             {ok, {data, Data}};
%         {grpc_trailers, StreamId, Trailers} ->
%             {ok, {trailers, Trailers}};
%         {grpc_closed, StreamId} ->
%             {error, closed};
%         {grpc_error, StreamId, Reason} ->
%             {error, Reason};
%         {'DOWN', MonitorRef, process, Pid, _Reason} ->
%             case recv_(Pid, MonitorRef, StreamId, 0) of
%                 {error, timeout} ->
%                     {error, closed};
%                 Result ->
%                     Result
%             end
%     after
%         Timeout ->
%             {error, timeout}
%     end.

% %% @private
% recv_(Type, Pid, MonitorRef, StreamId, Timeout) ->
%     receive
%         {Type = grpc_headers, StreamId, Headers} ->
%             {ok, {headers, Headers}};
%         {Type = grpc_data, StreamId, Data} ->
%             {ok, {data, Data}};
%         {Type = grpc_trailers, StreamId, Trailers} ->
%             {ok, {trailers, Trailers}};
%         {grpc_closed, StreamId} ->
%             {error, closed};
%         {grpc_error, StreamId, Reason} ->
%             {error, Reason};
%         {'DOWN', MonitorRef, process, Pid, _Reason} ->
%             case recv_(Type, Pid, MonitorRef, StreamId, 0) of
%                 {error, timeout} ->
%                     {error, closed};
%                 Result ->
%                     Result
%             end
%     after
%         Timeout ->
%             {error, timeout}
%     end.

% %% @private
% flush_(StreamId) ->
%     receive
%         {T, StreamId, _} when T =:= grpc_headers orelse T =:= grpc_data orelse T =:= grpc_trailers orelse T =:= grpc_error ->
%             flush_(StreamId);
%         {T, StreamId} when T =:= grpc_closed ->
%             flush_(StreamId)
%     after
%         0 ->
%             ok
%     end.

% %% @private
% notify_init(ClientPid) when is_pid(ClientPid) ->
%     ClientMon = erlang:monitor(process, ClientPid),
%     receive
%         {ClientPid, StreamPid} when is_pid(StreamPid) ->
%             StreamMon = erlang:monitor(process, StreamPid),
%             notify_loop(#{client_pid => ClientPid,
%                           client_mon => ClientMon,
%                           stream_pid => StreamPid,
%                           stream_mon => StreamMon})
%     end.

% %% @private
% notify_loop(State = #{client_pid := ClientPid,
%                       client_mon := ClientMon,
%                       stream_pid := StreamPid,
%                       stream_mon := StreamMon}) ->
%     receive
%         {'DOWN', ClientMon, process, ClientPid, Reason} ->
%             %% Client has died, exit with same reason.
%             exit(Reason);
%         {'DOWN', StreamMon, process, StreamPid, Reason} ->
%             %% Stream has died, exit with same reason.
%             exit(Reason);
%         Message ->
%             %% Forward all other messages to Stream.
%             StreamPid ! Message,
%             notify_loop(State)
%     end.

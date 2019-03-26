-module(grpcbox_client_stream).

-behaviour(h2_stream).

-export(['__struct__'/0,
         '__struct__'/1,
         get_private/2,
         get_private/3,
         put_private/3,
         update_private/4,

         new_stream/5,
         send_msg/2,
         recv_msg/2,

         send_data/2,
         send_data_end_stream/2,
         recv/2,
         recv/3,
         close_and_flush/1,

         init/3,
         on_receive_headers/2,
         on_send_push_promise/2,
         on_receive_data/2,
         on_end_stream/1,
         handle_info/2,

         notify_init/1]).

-include("grpcbox.hrl").

-type t() :: #{'__struct__' := ?MODULE,
               channel := grpcbox_channel:t(),
               stream_id := non_neg_integer(),
               stream_pid := pid(),
               service_def := #grpcbox_def{},
               encoding := grpcbox:encoding(),
               stream_interceptor := grpcbox_client_stream_interceptor:t(),
               private := map()}.

-export_type([t/0]).

-define(headers(Scheme, Host, Path, Encoding, MessageType, MD), [{<<":method">>, <<"POST">>},
                                                                 {<<":path">>, Path},
                                                                 {<<":scheme">>, Scheme},
                                                                 {<<":authority">>, Host},
                                                                 {<<"grpc-encoding">>, Encoding},
                                                                 {<<"grpc-message-type">>, MessageType},
                                                                 {<<"content-type">>, <<"application/grpc+proto">>},
                                                                 {<<"user-agent">>, grpcbox:user_agent()},
                                                                 {<<"te">>, <<"trailers">>} | MD]).

-define(is_timeout(T), ((is_integer(T) andalso T >= 0) orelse T =:= infinity)).

'__struct__'() ->
    #{'__struct__' => ?MODULE,
      channel => nil,
      stream_id => nil,
      stream_pid => nil,
      service_def => nil,
      encoding => nil,
      stream_interceptor => nil,
      private => #{}}.

'__struct__'(List) when is_list(List) ->
    '__struct__'(maps:from_list(List));
'__struct__'(Map) when is_map(Map) ->
    maps:fold(fun maps:update/3, '__struct__'(), Map).

get_private(#{'__struct__' := ?MODULE,
              private := Private}, Key) ->
    maps:get(Key, Private).

get_private(#{'__struct__' := ?MODULE,
              private := Private}, Key, Default) ->
    maps:get(Key, Private, Default).

put_private(S0=#{'__struct__' := ?MODULE,
                 private := P0}, Key, Value) ->
    P1 = maps:put(Key, Value, P0),
    S0#{private := P1}.

update_private(S0=#{'__struct__' := ?MODULE,
                    private := P0}, Key, Initial, UpdateFun) when is_function(UpdateFun, 1) ->
    case maps:find(Key, P0) of
        {ok, V0} ->
            V1 = UpdateFun(V0),
            P1 = maps:put(Key, V1, P0),
            S0#{private := P1};
        error ->
            P1 = maps:put(Key, Initial, P0),
            S0#{private := P1}
    end.

new_stream(Ctx, Channel, Path, Def=#grpcbox_def{service=Service,
                                                message_type=MessageType,
                                                marshal_fun=MarshalFun,
                                                unmarshal_fun=UnMarshalFun}, Options) ->
    case grpcbox_subchannel:conn(Channel) of
        {ok, Conn, #{scheme := Scheme,
                     authority := Authority,
                     encoding := DefaultEncoding,
                     stats_handler := StatsHandler}} ->
            Encoding = maps:get(encoding, Options, DefaultEncoding),
            RequestHeaders = ?headers(Scheme, Authority, Path, encoding_to_binary(Encoding),
                                      MessageType, metadata_headers(Ctx)),
            ClientPid = self(),
            NotifyPid = spawn(?MODULE, notify_init, [ClientPid]),
            case h2_connection:new_stream(Conn, ?MODULE, [#{service => Service,
                                                            marshal_fun => MarshalFun,
                                                            unmarshal_fun => UnMarshalFun,
                                                            path => Path,
                                                            buffer => <<>>,
                                                            stats_handler => StatsHandler,
                                                            stats => #{},
                                                            client_pid => ClientPid,
                                                            notify_pid => NotifyPid}], NotifyPid) of
                {error, _Code} = Err ->
                    Err;
                {StreamId, Pid} ->
                    _ = h2_connection:send_headers(Conn, StreamId, RequestHeaders),
                    {ok, '__struct__'(#{channel => Conn,
                                        stream_id => StreamId,
                                        stream_pid => Pid,
                                        service_def => Def,
                                        encoding => Encoding})}
            end;
        {error, _}=Error ->
            Error
    end.

send_msg(Stream = #{'__struct__' := ?MODULE}, Input) ->
    send_data(Stream, Input).

recv_msg(Stream = #{'__struct__' := ?MODULE}, Timeout) when ?is_timeout(Timeout) ->
    case recv(grpc_data, Stream, Timeout) of
        {ok, {data, Data}} ->
            {ok, Data};
        {error, closed} ->
            case recv(grpc_trailers, Stream, Timeout) of
                {ok, {trailers, {_Status = <<"0">>, _Message, _Metadata}}} ->
                    {error, closed};
                {ok, {trailers, {Status, Message, _Metadata}}} ->
                    {error, {Status, Message}};
                Error = {error, _Reason} ->
                    Error
            end;
        Error = {error, _Reason} ->
            Error
    end.

send_data(#{'__struct__' := ?MODULE,
            channel := Conn,
            stream_id := StreamId,
            encoding := Encoding,
            service_def := #grpcbox_def{marshal_fun=MarshalFun}}, Input) ->
    OutFrame = grpcbox_frame:encode(Encoding, MarshalFun(Input)),
    h2_connection:send_body(Conn, StreamId, OutFrame, [{send_end_stream, false}]).

send_data_end_stream(#{'__struct__' := ?MODULE,
                       channel := Conn,
                       stream_id := StreamId,
                       encoding := Encoding,
                       service_def := #grpcbox_def{marshal_fun=MarshalFun}}, Input) ->
    OutFrame = grpcbox_frame:encode(Encoding, MarshalFun(Input)),
    h2_connection:send_body(Conn, StreamId, OutFrame, [{send_end_stream, true}]).

                                                % recv_msg(S=#{stream_id := Id,
                                                %              stream_pid := Pid}, Timeout) ->
                                                %     receive
                                                %         {data, Id, V} ->
                                                %             {ok, V};
                                                %         {'DOWN', _Ref, process, Pid, _Reason} ->
                                                %             case grpcbox_client:recv_trailers(S, 0) of
                                                %                 {ok, {<<"0">> = _Status, _Message, _Metadata}} ->
                                                %                     stream_finished;
                                                %                 {ok, {Status, Message, _Metadata}} ->
                                                %                     {error, {Status, Message}};
                                                %                 timeout ->
                                                %                     stream_finished
                                                %             end
                                                %     after Timeout ->
                                                %             case erlang:is_process_alive(Pid) of
                                                %                 true ->
                                                %                     timeout;
                                                %                 false ->
                                                %                     stream_finished
                                                %             end
                                                %     end.

recv(#{'__struct__' := ?MODULE,
       stream_pid := Pid,
       stream_id := StreamId}, Timeout) when is_pid(Pid) andalso ?is_timeout(Timeout) ->
    case erlang:is_process_alive(Pid) of
        true ->
            MonitorRef = erlang:monitor(process, Pid),
            Result = recv_(Pid, MonitorRef, StreamId, Timeout),
            _ = erlang:demonitor(MonitorRef, [flush]),
            Result;
        false ->
            case recv_(nil, nil, StreamId, 0) of
                {error, timeout} ->
                    {error, closed};
                Result ->
                    Result
            end
    end.

recv(Type, #{'__struct__' := ?MODULE,
             stream_pid := Pid,
             stream_id := StreamId}, Timeout) when is_pid(Pid) andalso ?is_timeout(Timeout) ->
    case erlang:is_process_alive(Pid) of
        true ->
            MonitorRef = erlang:monitor(process, Pid),
            Result = recv_(Type, Pid, MonitorRef, StreamId, Timeout),
            _ = erlang:demonitor(MonitorRef, [flush]),
            Result;
        false ->
            case recv_(Type, nil, nil, StreamId, 0) of
                {error, timeout} ->
                    {error, closed};
                Result ->
                    Result
            end
    end.

close_and_flush(#{'__struct__' := ?MODULE,
                  channel := Conn,
                  stream_pid := Pid,
                  stream_id := StreamId}) ->
    ok = h2_connection:send_body(Conn, StreamId, <<>>, [{send_end_stream, true}]),
    case erlang:is_process_alive(Pid) of
        true ->
            MonitorRef = erlang:monitor(process, Pid),
            Pid ! close,
            receive
                {'DOWN', MonitorRef, process, Pid, _Reason} ->
                    ok
            after
                500 ->
                    ok = h2_stream:stop(Pid),
                    receive
                        {'DOWN', MonitorRef, process, Pid, _Reason} ->
                            ok
                    after
                        500 ->
                            _ = erlang:exit(Pid, kill),
                            _ = erlang:demonitor(Pid, [flush]),
                            ok
                    end
            end;
        false ->
            ok
    end,
    flush_(StreamId).

                                                % recv_data(Stream, Timeout) ->
                                                %     recv(grpc_data, Stream, Timeout).

metadata_headers(Ctx) ->
    case ctx:deadline(Ctx) of
        D when D =:= undefined ; D =:= infinity ->
            grpcbox_utils:encode_headers(maps:to_list(grpcbox_metadata:from_outgoing_ctx(Ctx)));
        {T, _} ->
            Timeout = {<<"grpc-timeout">>, <<(integer_to_binary(T - erlang:monotonic_time()))/binary, "S">>},
            grpcbox_utils:encode_headers([Timeout | maps:to_list(grpcbox_metadata:from_outgoing_ctx(Ctx))])
    end.

%% callbacks

init(_, StreamId, [_, State=#{path := Path, client_pid := ClientPid, notify_pid := NotifyPid}]) ->
    _ = process_flag(trap_exit, true),
    true = link(NotifyPid),
    NotifyPid ! {ClientPid, self()},
    Ctx1 = ctx:with_value(ctx:new(), grpc_client_method, Path),
    State1 = stats_handler(Ctx1, rpc_begin, {}, State),
    {ok, State1#{stream_id => StreamId}}.

on_receive_headers(H, State=#{resp_headers := _,
                              ctx := Ctx,
                              stream_id := StreamId,
                              client_pid := Pid}) ->
    Status = proplists:get_value(<<"grpc-status">>, H, undefined),
    Message = proplists:get_value(<<"grpc-message">>, H, undefined),
    Metadata = grpcbox_utils:headers_to_metadata(H),
    Pid ! {grpc_trailers, StreamId, {Status, Message, Metadata}},
    Ctx1 = ctx:with_value(Ctx, grpc_client_status, grpcbox_utils:status_to_string(Status)),
    {ok, State#{ctx => Ctx1,
                resp_trailers => H}};
on_receive_headers(H, State=#{stream_id := StreamId,
                              ctx := Ctx,
                              client_pid := Pid}) ->
    Encoding = proplists:get_value(<<"grpc-encoding">>, H, identity),
    Metadata = grpcbox_utils:headers_to_metadata(H),
    Pid ! {grpc_headers, StreamId, Metadata},
    %% TODO: better way to know if it is a Trailers-Only response?
    %% maybe chatterbox should include information about the end of the stream
    case proplists:get_value(<<"grpc-status">>, H, undefined) of
        undefined ->
            {ok, State#{resp_headers => H,
                        encoding => encoding_to_atom(Encoding)}};
        Status ->
            Message = proplists:get_value(<<"grpc-message">>, H, undefined),
            Pid ! {grpc_trailers, StreamId, {Status, Message, Metadata}},
            Ctx1 = ctx:with_value(Ctx, grpc_client_status, grpcbox_utils:status_to_string(Status)),
            {ok, State#{resp_headers => H,
                        ctx => Ctx1,
                        status => Status,
                        encoding => encoding_to_atom(Encoding)}}
    end.

on_send_push_promise(_Headers, State) ->
    {ok, State}.

on_receive_data(Data, State=#{stream_id := StreamId,
                              client_pid := Pid,
                              buffer := Buffer,
                              encoding := Encoding,
                              unmarshal_fun := UnmarshalFun}) ->
    {Remaining, Messages} = grpcbox_frame:split(<<Buffer/binary, Data/binary>>, Encoding),
    _ = [Pid ! {grpc_data, StreamId, UnmarshalFun(Message)} || Message <- Messages],
    {ok, State#{buffer => Remaining}};
on_receive_data(_Data, State) ->
    {ok, State}.

on_end_stream(State=#{stream_id := StreamId,
                      ctx := Ctx,
                      client_pid := Pid}) ->
                                                % io:format("STREAM END~n"),
    Pid ! {grpc_closed, StreamId},
    State1 = stats_handler(Ctx, rpc_end, {}, State),
    {ok, State1}.

handle_info(close, State) ->
    ok = h2_stream:stop(self()),
    State;
handle_info(Info, State) ->
                                                % io:format("GOT INFO ~p~n", [Info]),
    State.

%%

stats_handler(Ctx, _, _, State=#{stats_handler := undefined}) ->
    State#{ctx => Ctx};
stats_handler(Ctx, Event, Stats, State=#{stats_handler := StatsHandler,
                                         stats := StatsState}) ->
    {Ctx1, StatsState1} = StatsHandler:handle(Ctx, client, Event, Stats, StatsState),
    State#{ctx => Ctx1,
           stats => StatsState1}.

encoding_to_atom(identity) -> identity;
encoding_to_atom(<<"identity">>) -> identity;
encoding_to_atom(<<"gzip">>) -> gzip;
encoding_to_atom(<<"deflate">>) -> deflate;
encoding_to_atom(<<"snappy">>) -> snappy;
encoding_to_atom(Custom) -> binary_to_atom(Custom, latin1).

encoding_to_binary(identity) -> <<"identity">>;
encoding_to_binary(gzip) -> <<"gzip">>;
encoding_to_binary(deflate) -> <<"deflate">>;
encoding_to_binary(snappy) -> <<"snappy">>;
encoding_to_binary(Custom) -> atom_to_binary(Custom, latin1).

%% @private
recv_(Pid, MonitorRef, StreamId, Timeout) ->
    receive
        {grpc_headers, StreamId, Headers} ->
            {ok, {headers, Headers}};
        {grpc_data, StreamId, Data} ->
            {ok, {data, Data}};
        {grpc_trailers, StreamId, Trailers} ->
            {ok, {trailers, Trailers}};
        {grpc_closed, StreamId} ->
            {error, closed};
        {grpc_error, StreamId, Reason} ->
            {error, Reason};
        {'DOWN', MonitorRef, process, Pid, _Reason} ->
            case recv_(Pid, MonitorRef, StreamId, 0) of
                {error, timeout} ->
                    {error, closed};
                Result ->
                    Result
            end
    after
        Timeout ->
            {error, timeout}
    end.

%% @private
recv_(Type, Pid, MonitorRef, StreamId, Timeout) ->
    receive
        {Type = grpc_headers, StreamId, Headers} ->
            {ok, {headers, Headers}};
        {Type = grpc_data, StreamId, Data} ->
            {ok, {data, Data}};
        {Type = grpc_trailers, StreamId, Trailers} ->
            {ok, {trailers, Trailers}};
        {grpc_closed, StreamId} ->
            {error, closed};
        {grpc_error, StreamId, Reason} ->
            {error, Reason};
        {'DOWN', MonitorRef, process, Pid, _Reason} ->
            case recv_(Type, Pid, MonitorRef, StreamId, 0) of
                {error, timeout} ->
                    {error, closed};
                Result ->
                    Result
            end
    after
        Timeout ->
            {error, timeout}
    end.

%% @private
flush_(StreamId) ->
    receive
        {T, StreamId, _} when T =:= grpc_headers orelse T =:= grpc_data orelse T =:= grpc_trailers orelse T =:= grpc_error ->
            flush_(StreamId);
        {T, StreamId} when T =:= grpc_closed ->
            flush_(StreamId)
    after
        0 ->
            ok
    end.

%% @private
notify_init(ClientPid) when is_pid(ClientPid) ->
    ClientMon = erlang:monitor(process, ClientPid),
    receive
        {ClientPid, StreamPid} when is_pid(StreamPid) ->
            StreamMon = erlang:monitor(process, StreamPid),
            notify_loop(#{client_pid => ClientPid,
                          client_mon => ClientMon,
                          stream_pid => StreamPid,
                          stream_mon => StreamMon})
    end.

%% @private
notify_loop(State = #{client_pid := ClientPid,
                      client_mon := ClientMon,
                      stream_pid := StreamPid,
                      stream_mon := StreamMon}) ->
    receive
        {'DOWN', ClientMon, process, ClientPid, Reason} ->
                                                % Client has died, exit with same reason.
            exit(Reason);
        {'DOWN', StreamMon, process, StreamPid, Reason} ->
                                                % Stream has died, exit with same reason.
            exit(Reason);
        Message ->
                                                % Forward all other messages to Stream.
            StreamPid ! Message,
            notify_loop(State)
    end.

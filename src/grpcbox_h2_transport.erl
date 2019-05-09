-module(grpcbox_h2_transport).

-export([accept_stream/2,
         init_stream/2,
         send_initial_metadata/2,
         recv_initial_metadata/2,
         send_message/2,
         recv_message/2,
         send_trailing_metadata/2,
         recv_trailing_metadata/2]).
         % cancel_stream/2,
         % collect_stats/1,
         % on_complete/1]).

accept_stream(Stream0=#{kind := server,
                        env := Env0,
                        transport_pid := nil,
                        sent_initial_metadata := false,
                        recv_initial_metadata := false,
                        sent_trailing_metadata := false,
                        recv_trailing_metadata := false}, Options) ->
    Env1 = Env0#{?MODULE => Options},
    TransportPid = self(),
    Stream1 = Stream0#{env := Env1,
                       transport_pid := TransportPid},
    {ok, Stream1}.

init_stream(Stream0=#{kind := client,
                      channel := Channel,
                      method := Method,
                      definition := #service_def{message_type=MessageType},
                      connection_pid := nil,
                      transport_pid := nil,
                      sent_initial_metadata := false,
                      recv_initial_metadata := false,
                      sent_trailing_metadata := false,
                      recv_trailing_metadata := false}, Options) ->
    case grpcbox_subchannel:start_rpc(Channel) of
        {ok, ConnectionPid, #{scheme := Scheme,
                              authority := Authority,
                              encoding := DefaultEncoding,
                              user_agent := UserAgent}} ->
            SentEncoding = maps:get(encoding, Options, DefaultEncoding),
            RequestHeaders0 = #{<<":authority">> => Authority,
                                <<":method">> => <<"POST">>,
                                <<":path">> => Method,
                                <<":scheme">> => Scheme,
                                <<"content-type">> => <<"application/grpc+proto">>,
                                <<"grpc-encoding">> => encoding_to_binary(SentEncoding),
                                <<"grpc-message-type">> => MessageType,
                                <<"te">> => <<"trailers">>,
                                <<"user-agent">> => UserAgent},
            RequestHeaders1 = extra_request_headers(Stream0, RequestHeaders0, [deadline]),
            TransportPid = self(),
            Stream1 = merge_request_headers(Stream0#{transport_pid := TransportPid}, RequestHeaders1),
            case h2_connection:new_stream(ConnectionPid, grpcbox_h2_stream, [Stream1, Options], TransportPid) of
                StreamError = {error, _ErrorCode} ->
                    StreamError;
                {StreamId, StreamPid} ->
                    Stream2 = Stream1#{connection_pid := ConnectionPid,
                                       encoding := Encoding,
                                       stream_id := StreamId,
                                       stream_pid := StreamPid},
                    {ok, Stream2}
            end;
        ChannelError = {error, _} ->
            ChannelError
    end.

send_initial_metadata(_Stream=#{sent_initial_metadata := true}, _Metadata) ->
    erlang:error(badseq, {sent_initial_metadata, true});
send_initial_metadata(Stream0=#{kind := client, env := Env0=#{request_headers := RequestHeaders0}}, Metadata) ->
    RequestHeaders1 = maps:to_list(RequestHeaders0) ++ grpcbox_utils:encode_headers(maps:to_list(Metadata)),
    Env1 = Env0#{request_headers := RequestHeaders1},
    Stream1 = send_headers(Stream0#{env := Env1}, RequestHeaders1),
    {ok, Stream1};
send_initial_metadata(Stream0=#{kind := server, env := Env0=#{response_headers := ResponseHeaders0}}, Metadata) ->
    ResponseHeaders1 = maps:to_list(ResponseHeaders0) ++ grpcbox_utils:encode_headers(maps:to_list(Metadata)),
    Env1 = Env0#{response_headers := ResponseHeaders1},
    Stream1 = send_headers(Stream0#{env := Env1}, ResponseHeaders1),
    {ok, Stream1}.

recv_initial_metadata(_Stream=#{recv_initial_metadata := true}, _Metadata) ->
    erlang:error(badseq, {recv_initial_metadata, true});
recv_initial_metadata(Stream0=#{kind := client}, Headers) ->
    Encoding = proplists:get_value(<<"grpc-encoding">>, Headers, identity),
    Metadata = grpcbox_utils:headers_to_metadata(Headers),
    Stream1 = Stream0#{encoding := encoding_to_atom(Encoding)},
    {ok, Metadata, Stream1#{recv_initial_metadata := true}};
recv_initial_metadata(Stream0=#{kind := server,
                                env := Env0=#{?MODULE := Options}}, Headers) ->
    {<<":method">>, <<"POST">>} = lists:keyfind(<<":method">>, 1, Headers),
    {<<":path">>, Method} = lists:keyfind(<<":path">>, 1, Headers),
    Metadata = grpcbox_utils:headers_to_metadata(Headers),
    Ctx0 = grpcbox_metadata:new_incoming_ctx(Metadata),
    Ctx1 =
        case get_header(<<"grpc-timeout">>, Headers) of
            infinity ->
                Ctx0;
            D when is_integer(D) andalso D >= 0 ->
                ctx:with_deadline_after(Ctx0, D, nanosecond)
        end,
    Ctx2 = ctx:with_value(Ctx1, grpc_server_method, Method),
    ContentType = get_header(<<"content-type">>, Headers),
    ResponseEncoding = get_header(<<"grpc-accept-encoding">>, Headers),
    RequestEncoding = get_header(<<"grpc-encoding">>, Headers),
    ResponseHeaders = #{<<":status">> => <<"200">>,
                        <<"content-type">> => content_type(ContentType),
                        <<"grpc-encoding">> => encoding_to_binary(ResponseEncoding),
                        <<"user-agent">> => UserAgent},
    Env1 = Env0#{request_headers => Headers, response_headers => ResponseHeaders},
    Stream1 = Stream0#{ctx := Ctx2, env := Env1, method := Method},
    {ok, OwnerPid} = grpcbox_service:start_rpc(Stream1, Options),
    Stream2 = Stream1#{owner_pid := OwnerPid},
    {ok, Metadata, Stream2#{recv_initial_metadata := true}}.

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

% % handle_service_lookup(Ctx, [Service, Method], State=#state{services_table=ServicesTable}) ->
% %     case ets:lookup(ServicesTable, {Service, Method}) of
% %         [M=#method{}] ->
% %             State1 = State#state{ctx=Ctx,
% %                                  method=M},
% %             handle_auth(Ctx, State1);
% %         _ ->
% %             end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"Method not found on server">>, State)
% %     end;
% % handle_service_lookup(_, _, State) ->
% %     State1 = State#state{resp_headers=[{<<":status">>, <<"200">>},
% %                                        {<<"user-agent">>, grpcbox:user_agent()}]},
% %     end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"failed parsing path">>, State1),
% %     {ok, State1}.

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

send_message(_Stream=#{sent_initial_metadata := false}, _Message) ->
    erlang:error(badseq, {sent_initial_metadata, false});
send_message(_Stream=#{sent_trailing_metadata := true}, _Message) ->
    erlang:error(badseq, {sent_trailing_metadata, true});
send_message(Stream0=#{connection_pid := ConnectionPid, stream_id := StreamId}, Message) ->
    {ok, Struct=#{payload := Payload}, Stream1} = grpcbox_message:send_message(Stream0, Message),
    ok = h2_connection:send_body(ConnectionPid, StreamId, Payload, [{send_end_stream, false}]),
    {ok, Struct, Stream1}.

send_trailing_metadata(_Stream=#{sent_trailing_metadata := true}, _Metadata) ->
    erlang:error(badseq, {sent_trailing_metadata, true});
send_trailing_metadata(Stream0=#{kind := client, connection_pid := ConnectionPid, stream_id := StreamId}, _Metadata) ->
    ok = h2_connection:send_body(ConnectionPid, StreamId, <<>>, [{send_end_stream, true}]),
    Stream1 = Stream0#{sent_trailing_metadata := true},
    {ok, Stream1}.

%%

%% @private
% duration_to_timeout()

%% @private
encoding_to_binary(identity) -> <<"identity">>;
encoding_to_binary(gzip) -> <<"gzip">>;
encoding_to_binary(deflate) -> <<"deflate">>;
encoding_to_binary(snappy) -> <<"snappy">>;
encoding_to_binary(Custom) -> atom_to_binary(Custom, latin1).

%% @private
extra_request_headers(Stream=#{ctx := Ctx}, Headers0, [deadline | Keys]) ->
    case duration_to_timeout(ctx:deadline(Ctx)) of
        infinity ->
            extra_request_headers(Stream, Headers0, Keys);
        {T, Unit} when is_integer(T) andalso is_binary(Unit) ->
            Value = <<(integer_to_binary(T))/binary, Unit/binary>>,
            Headers1 = Headers0#{<<"grpc-timeout">> => Value}),
            extra_request_headers(Stream, Headers1, Keys)
    end;
extra_request_headers(_Stream, Headers, []) ->
    Headers.

%% @private
get_header(Key = <<"content-type">>, Headers) ->
    case lists:keyfind(Key, 1, Headers) of
        {Key, <<"application/grpc">>} ->
            proto;
        {Key, <<"application/grpc+proto">>} ->
            proto;
        {Key, <<"application/grpc+json">>} ->
            json;
        {Key, <<"application/grpc+", _>>} ->
            ?THROW(?GRPC_STATUS_UNIMPLEMENTED, <<"unknown content-type">>);
        false ->
            proto
    end;
get_header(Key, Headers) when Key =:= <<"grpc-accept-encoding">>; Key =:= <<"grpc-encoding">> ->
    case lists:keyfind(Key, 1, Headers) of
        {Key, <<"deflate", _/binary>>} ->
            deflate;
        {Key, <<"gzip", _/binary>>} ->
            gzip;
        {Key, <<"identity", _/binary>>} ->
            identity;
        {Key, <<"snappy", _/binary>>} ->
            snappy;
        {Key, _} ->
            ?THROW(?GRPC_STATUS_UNIMPLEMENTED, <<"unknown encoding">>);
        false ->
            identity
    end;
get_header(Key = <<"grpc-timeout">>, Headers) ->
    case lists:keyfind(Key, 1, Headers) of
        {Key, T} when is_binary(T) ->
            {I, U} = string:to_integer(T),
            timeout_to_duration({I, U})
        false ->
            infinity
    end.

%% @private
merge_request_headers(Stream0=#{env := Env0=#{request_headers := RequestHeaders0}}, NewRequestHeaders) ->
    RequestHeaders1 = maps:merge(RequestHeaders0, NewRequestHeaders),
    Env1 = Env0#{request_headers := RequestHeaders1},
    State1 = State0#{env := Env1};
    State1;
merge_request_headers(Stream0=#{env := Env0}, RequestHeaders) ->
    Env1 = Env0#{request_headers => RequestHeaders},
    State1 = State0#{env := Env1};
    State1.

% % parse_options(<<"grpc-encoding">>, Headers) ->
% %     parse_encoding(<<"grpc-encoding">>, Headers);
% % parse_options(<<"grpc-accept-encoding">>, Headers) ->
% %     parse_encoding(<<"grpc-accept-encoding">>, Headers).

% % parse_options(<<"grpc-timeout">>, Headers) ->
% %     case proplists:get_value(<<"grpc-timeout">>, Headers, infinity) of
% %         infinity ->
% %             infinity;
% %         T ->
% %             {I, U} = string:to_integer(T),
% %             timeout_to_duration(I, U)
% %     end;
% % parse_options(<<"content-type">>, Headers) ->
% %     case proplists:get_value(<<"content-type">>, Headers, undefined) of
% %         undefined ->
% %             proto;
% %         <<"application/grpc">> ->
% %             proto;
% %         <<"application/grpc+proto">> ->
% %             proto;
% %         <<"application/grpc+json">> ->
% %             json;
% %         <<"application/grpc+", _>> ->
% %             ?THROW(?GRPC_STATUS_UNIMPLEMENTED, <<"unknown content-type">>)
% %     end;
% % parse_options(<<"grpc-encoding">>, Headers) ->
% %     parse_encoding(<<"grpc-encoding">>, Headers);
% % parse_options(<<"grpc-accept-encoding">>, Headers) ->
% %     parse_encoding(<<"grpc-accept-encoding">>, Headers).

%% @private
send_headers(Stream=#{connection_pid := ConnectionPid, stream_id := StreamId}, Headers) when is_pid(ConnectionPid) ->
    ok = h2_connection:send_headers(ConnectionPid, StreamId, Headers, [{send_end_stream, false}]),
    Stream#{sent_initial_metadata := true}.

%% @private
duration_to_timeout(D) when D =:= undefined; D =:= infinity ->
    infinity;
duration_to_timeout(T) when is_integer(T) ->
    case T of
        _ when T =< 0 -> {1, <<"n">>};
        _ when T rem 3600000000000 =:= 0 -> {T div 3600000000000, <<"H">>};
        _ when T rem 60000000000 =:= 0 -> {T div 60000000000, <<"M">>};
        _ when T rem 1000000000 =:= 0 -> {T div 1000000000, <<"S">>};
        _ when T rem 1000000 =:= 0 -> {T div 1000000, <<"m">>};
        _ when T rem 1000 =:= 0 -> {T div 1000, <<"u">>};
        _ -> {T, <<"n">>}
    end;
duration_to_timeout({T, _Offset}) when is_integer(T) ->
    duration_to_timeout(T - erlang:monotonic_time()).

%% @private
timeout_to_duration({T, <<"H">>}) ->
    erlang:convert_time_unit(timer:hours(T), millisecond, nanosecond);
timeout_to_duration({T, <<"M">>}) ->
    erlang:convert_time_unit(timer:minutes(T), millisecond, nanosecond);
timeout_to_duration({T, <<"S">>}) ->
    erlang:convert_time_unit(T, second, nanosecond);
timeout_to_duration({T, <<"m">>}) ->
    erlang:convert_time_unit(T, millisecond, nanosecond);
timeout_to_duration({T, <<"u">>}) ->
    erlang:convert_time_unit(T, microsecond, nanosecond);
timeout_to_duration({T, <<"n">>}) ->
    T.

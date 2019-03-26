%%%-------------------------------------------------------------------
%% @doc grpc client
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_client).

-export([unary/6,
         unary/5,
         stream/4,
         stream/5,

         send/2,
         send_data/2,
         send_data_end_stream/2,
         send_trailers_end_stream/2,
         recv_headers/1,
         recv_headers/2,
         recv_data/1,
         recv_data/2,
         recv_trailers/1,
         recv_trailers/2,

                                                % close_and_recv/1,
                                                % close_and_recv/2,
         close_send/1]).

-include_lib("chatterbox/include/http2.hrl").
-include("grpcbox.hrl").

-type options() :: #{channel => grpcbox_channel:t(),
                     encoding => grpcbox:encoding()}.

-type unary_interceptor() :: term().
-type stream_interceptor() :: term().
-type interceptor() :: unary_interceptor() | stream_interceptor().

-type stream() :: #{channel => pid(),
                    stream_id => stream_id(),
                    stream_pid => pid(),
                    monitor_ref => reference(),
                    service_def => #grpcbox_def{},
                    encoding => grpcbox:encoding()}.

-export_type([stream/0,
              options/0,
              unary_interceptor/0,
              stream_interceptor/0,
              interceptor/0]).

-define(is_timeout(T), ((is_integer(T) andalso T >= 0) orelse T =:= infinity)).

-define(DEFAULT_RECV_TIMEOUT, 500).

get_channel(Options, Type) ->
    Channel = maps:get(channel, Options, default_channel),
    grpcbox_channel:pick(Channel, Type).

unary(Ctx, Service, Method, Input, Def, Options) ->
    unary(Ctx, filename:join([<<>>, Service, Method]), Input, Def, Options).

unary(Ctx, Path, Input, Def, Options) ->
    case get_channel(Options, unary) of
        {ok, {Channel, Interceptor}} ->
            Handler = fun(Ctx1, Input1) ->
                              unary_init(Ctx1, Channel, Path, Input1, Def, Options)
                      end,
            case Interceptor of
                undefined ->
                    Handler(Ctx, Input);
                _ ->
                    Interceptor(Ctx, Channel, Handler, Path, Input, Def, Options)
            end;
        {error, _Reason}=Error ->
            Error
    end.

%% no input: bidrectional
stream(Ctx, Path, Def, Options) ->
    case get_channel(Options, stream) of
        {ok, {Channel, Interceptor}} ->
            grpcbox_client_stream_interceptor:new_stream(Ctx, Channel, Interceptor, Path, Def, fun grpcbox_client_stream:new_stream/5, Options);
                                                % case Interceptor of
                                                %     undefined ->
                                                %         grpcbox_client_stream:new_stream(Ctx, Channel, Path, Def, Options);
                                                %     #{new_stream := NewStream} ->
                                                %         case NewStream(Ctx, Channel, Path, Def, fun grpcbox_client_stream:new_stream/5, Options) of
                                                %             {ok, Stream0} ->
                                                %                 Stream = Stream0#{stream_interceptor := Interceptor},
                                                %                 {ok, Stream};
                                                %             Error = {error, _Reason} ->
                                                %                 Error
                                                %         end
                                                % end;
        Error = {error, _Reason} ->
            Error
    end.

%% input given, stream response
stream(Ctx, Path, Input, Def, Options) ->
    case stream(Ctx, Path, Def, Options) of
        {ok, Stream} ->
            ok = send_data_end_stream(Stream, Input),
            {ok, Stream};
        Error = {error, _Reason} ->
            Error
    end.

                                                % send(Stream=#{stream_interceptor := #{send_msg := SendMsg}}, Input) ->
                                                %     SendMsg(Stream, fun grpcbox_client_stream:send_msg/2, Input);
                                                % send(Stream, Input) ->
                                                %     grpcbox_client_stream:send_msg(Stream, Input).

                                                % send_msg(Stream=#{stream_interceptor := #{send_msg := SendMsg}}, Streamer, Input) when is_function(Streamer, 2) ->
                                                %     SendMsg(Stream, Streamer, Input);
                                                % send_msg(Stream, Streamer, Input) when is_function(Streamer, 2) ->
                                                %     Streamer(Stream, Input).

send(Stream, Input) ->
    send_data(Stream, Input).

send_data(Stream, Input) ->
    grpcbox_client_stream_interceptor:send_msg(Stream, fun grpcbox_client_stream:send_data/2, Input).

send_data_end_stream(Stream, Input) ->
    grpcbox_client_stream_interceptor:send_msg(Stream, fun grpcbox_client_stream:send_data_end_stream/2, Input).

send_trailers_end_stream(#{channel := Conn,
                           stream_id := StreamId}, Trailers) ->
    ok = h2_connection:send_trailers(Conn, StreamId, Trailers, [{send_end_stream, true}]).

                                                % recv(Stream) ->
                                                %     recv(Stream, ?DEFAULT_RECV_TIMEOUT).
                                                % recv(Stream, Timeout) when ?is_timeout(Timeout) ->

recv_headers(Stream) ->
    recv_headers(Stream, ?DEFAULT_RECV_TIMEOUT).
recv_headers(Stream, Timeout) when ?is_timeout(Timeout) ->
    case grpcbox_client_stream:recv(grpc_headers, Stream, Timeout) of
        {ok, {headers, Headers}} ->
            {ok, Headers};
        Error = {error, _Reason} ->
            Error
    end.

recv_data(Stream) ->
    recv_data(Stream, ?DEFAULT_RECV_TIMEOUT).
recv_data(Stream, Timeout) when ?is_timeout(Timeout) ->
    grpcbox_client_stream_interceptor:recv_msg(Stream, fun grpcbox_client_stream:recv_msg/2, Timeout).

recv_trailers(Stream) ->
    recv_trailers(Stream, ?DEFAULT_RECV_TIMEOUT).
recv_trailers(Stream, Timeout) when ?is_timeout(Timeout) ->
    case grpcbox_client_stream:recv(grpc_trailers, Stream, Timeout) of
        {ok, {trailers, Trailers}} ->
            {ok, Trailers};
        Error = {error, _Reason} ->
            Error
    end.

                                                % recv_headers(Stream) ->
                                                %     recv_headers(Stream, ?DEFAULT_RECV_TIMEOUT).
                                                % recv_headers(Stream, Timeout) when ?is_timeout(Timeout) ->
                                                %     grpcbox_client_stream:recv(grpc_headers, Stream, Timeout).

                                                % recv_data(Stream) ->
                                                %     recv_data(Stream, ?DEFAULT_RECV_TIMEOUT).
                                                % recv_data(Stream=#{stream_interceptor := #{recv_msg := RecvMsg}}, Timeout) when ?is_timeout(Timeout) ->
                                                %     RecvMsg(Stream, fun grpcbox_client_stream:recv_msg/2, Timeout);
                                                % recv_data(Stream, Timeout) when ?is_timeout(Timeout) ->
                                                %     grpcbox_client_stream:recv_msg(Stream, Timeout).

                                                % send_data(Stream=#{stream_interceptor := #{send_msg := SendMsg}}, Input) ->
                                                %     SendMsg(Stream, fun grpcbox_client_stream:send_msg/2, Input);
                                                % send_data(Stream, Input) ->
                                                %     grpcbox_client_stream:send_msg(Stream, Input).

                                                % send_data_end_stream(Stream=#{stream_interceptor := #{send_msg := SendMsg}}, Input) ->
                                                %     SendMsg(Stream, fun grpcbox_client_stream:send_msg_end_stream/2, Input);
                                                % send_data_end_stream(Stream, Input) ->
                                                %     grpcbox_client_stream:send_msg_end_stream(Stream, Input).

                                                % send_trailers()

                                                % send_data_end

                                                % send_end_stream(Stream=#{stream_interceptor := #{send_msg := SendMsg}}, Input) ->
                                                %     SendMsg(Stream, fun grpcbox_client_stream:send_end_stream/2, Input);
                                                % send_end_stream(Stream, Input) ->
                                                %     grpcbox_client_stream:send_end_stream(Stream, Input).

                                                % handle_recv_data(Stream=#{stream_interceptor := #{recv_msg := RecvMsg}}, Input) ->
                                                %     Streamer = fun(_, _) -> {ok, Input} end,
                                                %     RecvMsg(Stream, Streamer, 0);
                                                % handle_recv_data(_Stream, Input) ->
                                                %     {ok, Input}.

                                                % recv_headers(Stream) ->
                                                %     recv_headers(Stream, ?DEFAULT_RECV_TIMEOUT).
                                                % recv_headers(Stream, Timeout) when ?is_timeout(Timeout) ->
                                                %     grpcbox_client_stream:recv(grpc_headers, Stream, Timeout).

                                                % recv_data(Stream) ->
                                                %     recv_data(Stream, ?DEFAULT_RECV_TIMEOUT).
                                                % recv_data(Stream=#{stream_interceptor := #{recv_msg := RecvMsg}}, Timeout) when ?is_timeout(Timeout) ->
                                                %     RecvMsg(Stream, fun grpcbox_client_stream:recv_msg/2, Timeout);
                                                % recv_data(Stream, Timeout) when ?is_timeout(Timeout) ->
                                                %     grpcbox_client_stream:recv_msg(Stream, Timeout).

                                                % recv_trailers(Stream) ->
                                                %     recv_trailers(Stream, ?DEFAULT_RECV_TIMEOUT).
                                                % recv_trailers(Stream, Timeout) when ?is_timeout(Timeout) ->
                                                %     grpcbox_client_stream:recv(grpc_trailers, Stream, Timeout).

                                                % recv_data(Stream) ->
                                                %     recv_data(Stream, ?DEFAULT_RECV_TIMEOUT).
                                                % recv_data(Stream = #{stream_interceptor := #{recv_msg := RecvMsg}}, Timeout) when ?is_timeout(Timeout) ->

                                                % recv_data(Stream, Timeout) when ?is_timeout(Timeout) ->


                                                % recv_data(Stream) ->
                                                %     recv_data(Stream, 500).
                                                % recv_data(Stream=#{stream_interceptor := #{recv_msg := RecvMsg}}, Timeout) ->
                                                %     RecvMsg(Stream, fun grpcbox_client_stream:recv_msg/2, Timeout);
                                                % recv_data(Stream, Timeout) ->
                                                %     grpcbox_client_stream:recv_msg(Stream, Timeout).

                                                % recv_headers(S) ->
                                                %     recv_headers(S, 500).
                                                % recv_headers(S, Timeout) ->
                                                %     recv(grpc_headers, S, Timeout).

                                                % close_and_recv(Stream) ->
                                                %     close_and_recv(Stream, 5000).

                                                % close_and_recv(Stream, Timeout) when ?is_timeout(Timeout) ->
                                                %     ok = close_send(Stream),
                                                %     recv_loop()
                                                %     case recv_end(Stream, Timeout) of
                                                %         ok ->


                                                % %% @private
                                                % recv_loop(Stream)

                                                % close_and_recv(Stream) ->
                                                %     ok = close_send(Stream),
                                                %     case recv_end(Stream, )

                                                % close_and_recv(Stream) ->
                                                %     close_send(Stream),
                                                %     case recv_end(Stream, 5000) of
                                                %         eos ->
                                                %             recv_data(Stream, 0);
                                                %         {error, _}=Error ->
                                                %             Error
                                                %     end.

close_send(#{channel := Conn,
             stream_id := StreamId}) ->
    ok = h2_connection:send_body(Conn, StreamId, <<>>, [{send_end_stream, true}]).

                                                % recv_data(Stream) ->
                                                %     recv_data(Stream, 500).
                                                % recv_data(Stream=#{stream_interceptor := #{recv_msg := RecvMsg}}, Timeout) ->
                                                %     RecvMsg(Stream, fun grpcbox_client_stream:recv_msg/2, Timeout);
                                                % recv_data(Stream, Timeout) ->
                                                %     grpcbox_client_stream:recv_msg(Stream, Timeout).

                                                % recv_headers(S) ->
                                                %     recv_headers(S, 500).
                                                % recv_headers(S, Timeout) ->
                                                %     recv(grpc_headers, S, Timeout).

                                                % recv_trailers(S) ->
                                                %     recv_trailers(S, 500).
                                                % recv_trailers(S, Timeout) ->
                                                %     recv(grpc_trailers, S, Timeout).

                                                % recv(Type, Stream, Timeout) ->
                                                %     grpcbox_client_stream:recv_type(Type, Stream, Timeout).

                                                % recv(Type, #{stream_id := Id,
                                                %              monitor_ref := Ref,
                                                %              stream_pid := Pid}, Timeout) ->
                                                %     receive
                                                %         {Type, Id, V} ->
                                                %             {ok, V};
                                                %         {'DOWN', Ref, process, Pid, _Reason} ->
                                                %             receive
                                                %                 {trailers, Id, {<<"0">>, _Message, Metadata}} ->
                                                %                     {ok, #{trailers => Metadata}};
                                                %                 {trailers, Id, {Status, Message, _Metadata}} ->
                                                %                     {error, {Status, Message}}
                                                %             after 0 ->
                                                %                     {error, unknown}
                                                %             end
                                                %     after Timeout ->
                                                %             timeout
                                                %     end.

                                                % recv_end(#{stream_id := StreamId,
                                                %            stream_pid := Pid,
                                                %            monitor_ref := Ref}, Timeout) ->
                                                %     receive
                                                %         {eos, StreamId} ->
                                                %             erlang:demonitor(Ref, [flush]),
                                                %             eos;
                                                %         {'DOWN', Ref, process, Pid, normal} ->
                                                %             %% this is sent by h2_connection after the stream process has ended
                                                %             receive
                                                %                 {'END_STREAM', StreamId} ->
                                                %                     eos
                                                %             after Timeout ->
                                                %                     {error, {stream_down, normal}}
                                                %             end;
                                                %         {'DOWN', Ref, process, Pid, Reason} ->
                                                %             {error, {stream_down, Reason}}
                                                %     after Timeout ->
                                                %             {error, timeout}
                                                %     end.

%% Unary handler.

%% @private
unary_init(Ctx, Channel, Path, Input, Def, Options) ->
    Timeout =
        case maps:get(timeout, Options, 5000) of
            T when is_integer(T) andalso T >= 0 ->
                T;
            T = infinity ->
                T
        end,
    Parent = self(),
    Tag = make_ref(),
    {ChildPid, ChildMon} = spawn_monitor(fun() ->
                                                 Result =
                                                     case grpcbox_client_stream:new_stream(Ctx, Channel, Path, Def, Options) of
                                                         {ok, Stream} ->
                                                             try send_data_end_stream(Stream, Input) of
                                                                 ok ->
                                                                     unary_loop(Stream, Timeout, nil, nil)
                                                             catch
                                                                 throw:Error={error, _Reason} ->
                                                                     Error
                                                             end;
                                                         Error = {error, _} ->
                                                             Error
                                                     end,
                                                 Parent ! {Tag, Result},
                                                 exit(normal)
                                         end),
    receive
        {Tag, Response} ->
            receive
                {'DOWN', ChildMon, process, ChildPid, _Reason} ->
                    ok
            after
                0 ->
                    _ = erlang:exit(ChildPid, timeout),
                    _ = erlang:demonitor(ChildMon, [flush]),
                    ok
            end,
            Response;
        {'DOWN', ChildMon, process, ChildPid, Reason} ->
            {error, {'EXIT', ChildPid, Reason}}
    after
        Timeout ->
            _ = erlang:exit(ChildPid, timeout),
            _ = erlang:demonitor(ChildMon, [flush]),
            {error, timeout}
    end.

                                                % %% @private
                                                % foo_loop() ->
                                                %     receive
                                                %         % Msg = {_, I, _} ->
                                                %         %     io:format("msg = ~p~n", [Msg]),
                                                %         %     foo_loop(S);
                                                %         % Msg = {_, I} ->
                                                %         %     io:format("msg = ~p~n", [Msg]),
                                                %         %     foo_loop(S);
                                                %         Msg ->
                                                %             io:format("msg = ~p~n", [Msg]),
                                                %             foo_loop()
                                                %     end.

%% @private
unary_loop(Stream, Timeout, H, D) ->
    case grpcbox_client_stream:recv(Stream, Timeout) of
        {ok, {headers, Headers}} when H =:= nil ->
            unary_loop(Stream, Timeout, Headers, nil);
        {ok, {data, Data}} when H =/= nil andalso D =:= nil ->
            unary_loop(Stream, Timeout, H, Data);
        {ok, {trailers, {<<"0">>, _, Metadata}}} ->
            {ok, D, #{headers => H, trailers => Metadata}};
        {ok, {trailers, {Status, Message, _Metadata}}} ->
            {error, {Status, Message}};
        {error, closed} when H =/= nil andalso D =/= nil ->
            {ok, D, #{headers => H, trailers => #{}}};
        Error = {error, _} ->
            Error
    end.

                                                % unary_loop(Stream, Timeout, nil, nil) ->
                                                %     % foo_loop(),
                                                %     case grpcbox_client_stream:recv(Stream, Timeout) of
                                                %         {ok, {headers, Headers}} ->
                                                %             % io:format("headers = ~p~n", [Headers]),
                                                %             unary_loop(Stream, Timeout, Headers, nil);
                                                %         {ok, {trailers, {Status, Message, _Metadata}}} ->
                                                %             {error, {Status, Message}};
                                                %         Error = {error, _} ->
                                                %             Error
                                                %     end;
                                                % unary_loop(Stream, Timeout, Headers, nil) ->
                                                %     case grpcbox_client_stream:recv(Stream, Timeout) of
                                                %         {ok, {data, Data}} ->
                                                %             unary_loop(Stream, Timeout, Headers, Data);
                                                %         {ok, {trailers, {Status, Message, _Metadata}}} ->
                                                %             {error, {Status, Message}};
                                                %         Error = {error, _} ->
                                                %             Error
                                                %     end;
                                                % unary_loop(Stream, Timeout, Headers, Data) ->
                                                %     case grpcbox_client_stream:recv(Stream, Timeout) of
                                                %         {ok, {trailers, {<<"0">>, _, Metadata}}} ->
                                                %             {ok, Data, #{headers => Headers, trailers => Metadata}};
                                                %         {ok, {trailers, {Status, Message, _Metadata}}} ->
                                                %             {error, {Status, Message}};
                                                %         Error = {error, _} ->
                                                %             Error
                                                %     end.

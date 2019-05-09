-module(grpcbox_service).

-export([start_rpc/2,
         init/1]).

-record(state, {
    parent = nil :: nil | pid(),
    stream = nil :: nil | grpcbox_stream:t(),
    options = nil :: nil | term()
}).

start_rpc(Stream=#{kind := server}, Options) ->
    proc_lib:start_link(?MODULE, init, [{self(), Stream, Options}]).

init({Parent, Stream, Options}) ->
    _ = erlang:process_flag(trap_exit, true),
    ok = proc_lib:init_ack(Parent, {ok, self()}),
    State = #state{
        parent = Parent,
        stream = Stream,
        options = Options
    },
    handle_service_lookup(State).
    % authenticate(Parent, Stream).

handle_service_lookup(Parent, Stream) ->
    case ets:lookup(ServicesTable, {Service, Method}) of
        [M=#method{}] ->
            % authenticate
        [] ->
            send_trailing_metadata(State, ?GRPC_STATUS_UNIMPLEMENTED, <<"Method not found on server">>, #{})
    end.

send_trailing_metadata(State, ErrorCode, Message, Metadata) ->
    Parent ! {send_trailing_metadata, self(), ErrorCode, Message, Metadata},
    ok.

service_init() ->
    receive
        {grpc_initial_metadata, Parent, Metadata} ->


% service_init(Method=#method{input={_, false}}) ->
%     receive
%         {Ref, Message} ->
%             Module:Function(Ref, )
%     case Method of
%         #method{input={_, false}} ->
%             receive
%     end.

% cancel_stream(State, )

% % end_stream(State) ->
% %     end_stream(?GRPC_STATUS_OK, <<>>, State).

% % end_stream(Status, Message, State=#state{headers_sent=false}) ->
% %     end_stream(Status, Message, send_headers(State));
% % end_stream(_Status, _Message, State=#state{trailers_sent=true}) ->
% %     {ok, State};
% % end_stream(Status, Message, State=#state{connection_pid=ConnPid,
% %                                          stream_id=StreamId,
% %                                          ctx=Ctx,
% %                                          resp_trailers=Trailers}) ->
% %     EncodedTrailers = grpcbox_utils:encode_headers(Trailers),
% %     h2_connection:send_trailers(ConnPid, StreamId, [{<<"grpc-status">>, Status},
% %                                                     {<<"grpc-message">>, Message} | EncodedTrailers],
% %                                 [{send_end_stream, true}]),
% %     Ctx1 = ctx:with_value(Ctx, grpc_server_status, grpcbox_utils:status_to_string(Status)),
% %     State1 = stats_handler(Ctx1, rpc_end, {}, State),
% %     {ok, State1#state{trailers_sent=true}}.

    % %     case ets:lookup(ServicesTable, {Service, Method}) of
    % %         [M=#method{}] ->
    % %             State1 = State#state{ctx=Ctx,
    % %                                  method=M},
    % %             handle_auth(Ctx, State1);
    % %         _ ->
    % %             end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"Method not found on server">>, State)
    % %     end;

% authenticate(Parent, Stream) ->


    % % handle_auth(_Ctx, State=#state{auth_fun=AuthFun,
    % %                                socket=Socket,
    % %                                method=#method{input={_, InputStreaming}}}) ->
    % %     case authenticate(sock:peercert(Socket), AuthFun) of
    % %         {true, _Identity} ->
    % %             case InputStreaming of
    % %                 true ->
    % %                     Ref = make_ref(),
    % %                     Pid = proc_lib:spawn_link(?MODULE, handle_streams,
    % %                                               [Ref, State#state{handler=self()}]),
    % %                     {ok, State#state{input_ref=Ref,
    % %                                      callback_pid=Pid}};
    % %                 _ ->
    % %                     {ok, State}
    % %             end;
    % %         _ ->
    % %             end_stream(?GRPC_STATUS_UNAUTHENTICATED, <<"">>, State)
    % %     end.

    % % authenticate(_, undefined) ->
    % %     {true, undefined};
    % % authenticate({ok, Cert}, Fun) ->
    % %     Fun(Cert);
    % % authenticate(_, _) ->
    % %     false.
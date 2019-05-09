-module(grpcbox_transport).

-export([accept_stream/2,
         init_stream/2,
         send_initial_metadata/2,
         recv_initial_metadata/2,
         send_message/2,
         recv_message/2,
         send_trailing_metadata/2,
         recv_trailing_metadata/2,
         cancel_stream/2,
         collect_stats/1,
         on_complete/1]).

% -type stream() :: grpcbox_stream:t().

% -type exec_simple() :: {ok, stream()}.
% -type exec_return(R) :: {ok, R, stream()}.
% -type exec_decode(Result, Rest) :: {ok, Result, Rest, stream()} | {more, Rest, stream()}.

% -type continue1(T) ::
%     fun((stream()) -> T).

% -type continue1_simple() :: continue1(exec_simple()).

% -type continue2(A, T) ::
%     fun((stream(), A) -> T).

% -type continue2_simple(A) :: continue2(A, exec_simple()).

% -type continue2_return(A, R) :: continue2(A, exec_return(R)).
% -type continue2_return(A) :: continue2_return(A, A).

% -type continue2_decode(Buffer, Result, Rest) :: continue2(Buffer, exec_decode(Result, Rest)).

% -type frame_tuple() :: {binary(), non_neg_integer(), non_neg_integer()}.

% -spec accept_stream(stream(), Options) -> exec_simple() when Options :: map().
accept_stream(Stream=#{kind := server}, Options) ->
    execute(Stream, accept_stream, 3, [Options]).

% -spec init_stream(stream(), Options) -> exec_simple() when Options :: map().
init_stream(Stream=#{kind := client}, Options) ->
    execute(Stream, init_stream, 3, [Options]).

% -spec send_initial_metadata(stream(), Metadata) -> exec_simple() when Metadata :: term().
send_initial_metadata(Stream, Metadata) ->
    execute(Stream, send_initial_metadata, 3, [Metadata]).

% -spec recv_initial_metadata(stream(), Metadata) -> exec_return(Metadata) when Metadata :: term().
recv_initial_metadata(Stream, Metadata) ->
    execute(Stream, recv_initial_metadata, 3, [Metadata]).

% -spec send_message(stream(), Message) -> exec_return(Result) when Message :: term(), Result :: grpcbox_message:sent().
send_message(Stream, Message) ->
    execute(Stream, send_message, 3, [Message]).

% -spec recv_message(stream(), Buffer) -> exec_decode(Result, Rest) when Buffer :: binary(), Result :: grpcbox_message:recv(), Rest :: binary().
recv_message(Stream, Buffer) ->
    execute(Stream, recv_message, 3, [Buffer]).

send_trailing_metadata(Stream, Metadata) ->
    execute(Stream, send_trailing_metadata, 3, [Metadata]).

% -spec recv_trailing_metadata(stream(), Metadata) -> exec_return(Metadata) when Metadata :: term().
recv_trailing_metadata(Stream, Metadata) ->
    execute(Stream, recv_trailing_metadata, 3, [Metadata]).

cancel_stream(Stream, ErrorCode) ->
    execute(Stream, cancel_stream, 3, [ErrorCode]).

collect_stats(Stream) ->
    execute(Stream, collect_stats, 2, []).

on_complete(Stream) ->
    execute(Stream, on_complete, 2, []).

% #{
%     incoming => #{
%         framing_bytes => 0,
%         data_bytes => 0,
%         header_bytes => 0
%     },
%     outgoing => #{
%         framing_bytes => 0,
%         data_bytes => 0,
%         header_bytes => 0
%     }
% }

% -spec grpc_recv_trailers(stream(), Trailers) -> exec_return(Trailers) when Trailers :: term().
% grpc_recv_trailers(Stream, Trailers) ->
%     execute(Stream, grpc_recv_trailers, 3, [Trailers]).

% -spec grpc_cancel(stream()) -> exec_simple().
% grpc_cancel(Stream) ->
%     execute(Stream, grpc_cancel, 2, []).

% -spec grpc_end_stream(stream()) -> exec_simple().
% grpc_end_stream(Stream) ->
%     execute(Stream, grpc_end_stream, 2, []).

% -spec grpc_terminate(stream(), Reason) -> exec_simple() when Reason :: term().
% grpc_terminate(Stream, Reason) ->
%     execute(Stream, grpc_terminate, 3, [Reason]).

%%

%% @private
execute(Stream=#{transport := Transport, interceptor := Interceptor}, Function, Arity, Arguments) when (length(Arguments) + 2) =:= Arity andalso is_map(Interceptor) ->
    case maps:get(Function, Interceptor) of
        [Callback | Callbacks] when is_function(Callback, Arity) ->
            Continue = create_continue_fun(Callbacks, Function, Arity),
            erlang:apply(Callback, [Stream, Continue | Arguments]);
        [] ->
            erlang:apply(Transport, Function, [Stream | Arguments])
    end;
execute(Stream=#{transport := Transport}, Function, Arity, Arguments) when (length(Arguments) + 2) =:= Arity ->
    erlang:apply(Transport, Function, [Stream | Arguments]).

%% @private
next(Stream, {[Callback | Callbacks], Function, Arity}, Arguments) when (length(Arguments) + 2) =:= Arity andalso is_function(Callback, Arity) ->
    Continue = create_continue_fun(Callbacks, Function, Arity),
    erlang:apply(Callback, [Stream, Continue | Arguments]);
next(Stream=#{transport := Transport}, {[], Function, Arity}, Arguments) when (length(Arguments) + 2) =:= Arity ->
    erlang:apply(Transport, Function, [Stream | Arguments]).

%% @private
create_continue_fun(Callbacks, Function, Arity = 2) ->
    fun(Stream) -> next(Stream, {Callbacks, Function, Arity}, []) end;
create_continue_fun(Callbacks, Function, Arity = 3) ->
    fun(Stream, Arg0) -> next(Stream, {Callbacks, Function, Arity}, [Arg0]) end.

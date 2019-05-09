-module(grpcbox_client_interceptor).

-export(['__struct__'/0,
         '__struct__'/1,
         new/1,
         chain/1,
         chain/2,

         grpc_init/2,
         grpc_send_headers/2,
         grpc_recv_headers/2,
         grpc_marshal_message/2,
         grpc_unmarshal_message/2,
         grpc_outbound_frame/2,
         grpc_inbound_frame/2,
         grpc_send_data/2,
         grpc_recv_data/2,
         grpc_recv_trailers/2,
         grpc_cancel/1,
         grpc_end_stream/1,
         grpc_terminate/2]).

-type stream() :: grpcbox_client_stream:t().

-type exec_simple() :: {ok, stream()}.
-type exec_return(R) :: {ok, R, stream()}.
-type exec_decode(Result, Rest) :: {ok, Result, Rest, stream()} | {more, Rest, stream()}.

-type continue1(T) ::
    fun((stream()) -> T).

-type continue1_simple() :: continue1(exec_simple()).

-type continue2(A, T) ::
    fun((stream(), A) -> T).

-type continue2_simple(A) :: continue2(A, exec_simple()).

-type continue2_return(A, R) :: continue2(A, exec_return(R)).
-type continue2_return(A) :: continue2_return(A, A).

-type continue2_decode(Buffer, Result, Rest) :: continue2(Buffer, exec_decode(Result, Rest)).

-type frame_tuple() :: {binary(), non_neg_integer(), non_neg_integer()}.

-callback grpc_init(stream(), continue2_simple(Options), Options) -> exec_simple() when Options :: map().
-callback grpc_send_headers(stream(), continue2_simple(Headers), Headers) -> exec_simple() when Headers :: term().
-callback grpc_recv_headers(stream(), continue2_return(Headers), Headers) -> exec_return(Headers) when Headers :: term().
-callback grpc_marshal_message(stream(), continue2_return(Unmarshalled, Marshalled), Unmarshalled) -> exec_return(Marshalled) when Marshalled :: binary(), Unmarshalled :: term().
-callback grpc_unmarshal_message(stream(), continue2_return(Marshalled, Unmarshalled), Marshalled) -> exec_return(Unmarshalled) when Unmarshalled :: term(), Marshalled :: binary().
-callback grpc_outbound_frame(stream(), continue2_return(Message, Result), Message) -> exec_return(Result) when Message :: binary(), Result :: frame_tuple().
-callback grpc_inbound_frame(stream(), continue2_decode(Buffer, Result, Rest), Buffer) -> exec_decode(Result, Rest) when Buffer :: binary(), Result :: frame_tuple(), Rest :: binary().
-callback grpc_send_data(stream(), continue2_simple(Message), Message) -> exec_simple() when Message :: term().
-callback grpc_recv_data(stream(), continue2_decode(Buffer, Result, Rest), Buffer) -> exec_decode(Result, Rest) when Buffer :: binary(), Result :: term(), Rest :: binary().
-callback grpc_recv_trailers(stream(), continue2_return(Trailers), Trailers) -> exec_return(Trailers) when Trailers :: term().
-callback grpc_cancel(stream(), continue1_simple()) -> exec_simple().
-callback grpc_end_stream(stream(), continue1_simple()) -> exec_simple().
-callback grpc_terminate(stream(), continue2_simple(Reason), Reason) -> exec_simple() when Reason :: term().

-optional_callbacks([grpc_init/3,
                     grpc_send_headers/3,
                     grpc_recv_headers/3,
                     grpc_marshal_message/3,
                     grpc_unmarshal_message/3,
                     grpc_outbound_frame/3,
                     grpc_inbound_frame/3,
                     grpc_send_data/3,
                     grpc_recv_data/3,
                     grpc_recv_trailers/3,
                     grpc_cancel/2,
                     grpc_end_stream/2,
                     grpc_terminate/3]).

'__struct__'() ->
    #{'__struct__' => ?MODULE,
      grpc_init => [],
      grpc_send_headers => [],
      grpc_recv_headers => [],
      grpc_marshal_message => [],
      grpc_unmarshal_message => [],
      grpc_outbound_frame => [],
      grpc_inbound_frame => [],
      grpc_send_data => [],
      grpc_recv_data => [],
      grpc_recv_trailers => [],
      grpc_cancel => [],
      grpc_end_stream => [],
      grpc_terminate => []}.

'__struct__'(List) when is_list(List) ->
    '__struct__'(maps:from_list(List));
'__struct__'(Map) when is_map(Map) ->
    maps:fold(fun validate_and_update/3, '__struct__'(), maps:without(['__struct__'], Map)).

new(Interceptor=#{'__struct__' := ?MODULE}) ->
    Interceptor;
new({Function, Arg}) when is_function(Function, 1) ->
    new(Function(Arg));
new(Module) when is_atom(Module) ->
    _ = code:ensure_loaded(Module),
    EmptyMap = maps:without(['__struct__'], '__struct__'()),
    {_, Map} = maps:fold(fun validate_module_and_update/3, {Module, EmptyMap}, EmptyMap),
    new(Map);
new(Map) when is_map(Map) ->
    '__struct__'(Map);
new(List = [_ | _]) ->
    chain(List).

chain([I]) ->
    new(I);
chain([A, B | Rest]) ->
    chain([chain(A, B) | Rest]).

chain(A0, B0) ->
    A1 = new(A0),
    B1 = maps:without(['__struct__'], new(B0)),
    maps:fold(fun validate_chain_and_update/3, A1, B1).

-spec grpc_init(stream(), Options) -> exec_simple() when Options :: map().
grpc_init(Stream, Options) ->
    execute(Stream, grpc_init, 3, [Options]).

-spec grpc_send_headers(stream(), Headers) -> exec_simple() when Headers :: term().
grpc_send_headers(Stream, Headers) ->
    execute(Stream, grpc_send_headers, 3, [Headers]).

-spec grpc_recv_headers(stream(), Headers) -> exec_return(Headers) when Headers :: term().
grpc_recv_headers(Stream, Headers) ->
    execute(Stream, grpc_recv_headers, 3, [Headers]).

-spec grpc_marshal_message(stream(), Unmarshalled) -> exec_return(Marshalled) when Marshalled :: binary(), Unmarshalled :: term().
grpc_marshal_message(Stream, Message) ->
    execute(Stream, grpc_marshal_message, 3, [Message]).

-spec grpc_unmarshal_message(stream(), Marshalled) -> exec_return(Unmarshalled) when Unmarshalled :: term(), Marshalled :: binary().
grpc_unmarshal_message(Stream, Message) ->
    execute(Stream, grpc_unmarshal_message, 3, [Message]).

-spec grpc_outbound_frame(stream(), Message) -> exec_return(Result) when Message :: binary(), Result :: frame_tuple().
grpc_outbound_frame(Stream, Message) ->
    execute(Stream, grpc_outbound_frame, 3, [Message]).

-spec grpc_inbound_frame(stream(), Buffer) -> exec_decode(Result, Rest) when Buffer :: binary(), Result :: frame_tuple(), Rest :: binary().
grpc_inbound_frame(Stream, Buffer) ->
    execute(Stream, grpc_inbound_frame, 3, [Buffer]).

-spec grpc_send_data(stream(), Message) -> exec_simple() when Message :: term().
grpc_send_data(Stream, Message) ->
    execute(Stream, grpc_send_data, 3, [Message]).

-spec grpc_recv_data(stream(), Buffer) -> exec_decode(Result, Rest) when Buffer :: binary(), Result :: term(), Rest :: binary().
grpc_recv_data(Stream, Buffer) ->
    execute(Stream, grpc_recv_data, 3, [Buffer]).

-spec grpc_recv_trailers(stream(), Trailers) -> exec_return(Trailers) when Trailers :: term().
grpc_recv_trailers(Stream, Trailers) ->
    execute(Stream, grpc_recv_trailers, 3, [Trailers]).

-spec grpc_cancel(stream()) -> exec_simple().
grpc_cancel(Stream) ->
    execute(Stream, grpc_cancel, 2, []).

-spec grpc_end_stream(stream()) -> exec_simple().
grpc_end_stream(Stream) ->
    execute(Stream, grpc_end_stream, 2, []).

-spec grpc_terminate(stream(), Reason) -> exec_simple() when Reason :: term().
grpc_terminate(Stream, Reason) ->
    execute(Stream, grpc_terminate, 3, [Reason]).

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

%% @private
validate_and_update(K, V = [], Acc) ->
    maps:update(K, V, Acc);
validate_and_update(K, V, Acc) when (K =:= grpc_cancel orelse K =:= grpc_end_stream) andalso is_list(V) ->
    Predicate = fun(Callback) -> is_function(Callback, 2) end,
    case lists:all(Predicate, V) of
        true ->
            maps:update(K, V, Acc);
        false ->
            erlang:error({badarg, [K, V, Acc]})
    end;
validate_and_update(K, V, Acc) when is_atom(K) andalso is_list(V) ->
    Predicate = fun(Callback) -> is_function(Callback, 3) end,
    case lists:all(Predicate, V) of
        true ->
            maps:update(K, V, Acc);
        false ->
            erlang:error({badarg, [K, V, Acc]})
    end.

%% @private
validate_chain_and_update(_Function, [], Acc) ->
    Acc;
validate_chain_and_update(Function, CallbacksB = [_ | _], Acc) ->
    CallbacksA = maps:get(Function, Acc),
    maps:update(Function, CallbacksA ++ CallbacksB, Acc).

%% @private
validate_module_and_update(Function, [], {Module, Acc}) when (Function =:= grpc_cancel orelse Function =:= grpc_end_stream) ->
    case erlang:function_exported(Module, Function, 2) of
        true ->
            {Module, maps:update(Function, [fun Module:Function/2], Acc)};
        false ->
            {Module, Acc}
    end;
validate_module_and_update(Function, [], {Module, Acc}) when is_atom(Function) ->
    case erlang:function_exported(Module, Function, 3) of
        true ->
            {Module, maps:update(Function, [fun Module:Function/3], Acc)};
        false ->
            {Module, Acc}
    end.

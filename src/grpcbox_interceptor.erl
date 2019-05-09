-module(grpcbox_interceptor).

-export(['__struct__'/0,
         '__struct__'/1,
         new/1,
         chain/1,
         chain/2]).

-type stream() :: grpcbox_stream:t().

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

-callback accept_stream(stream(), continue2_simple(Options), Options) -> exec_simple() when Options :: map().
-callback init_stream(stream(), continue2_simple(Options), Options) -> exec_simple() when Options :: map().
-callback send_initial_metadata(stream(), continue2_simple(Metadata), Metadata) -> exec_simple() when Metadata :: term().
-callback recv_initial_metadata(stream(), continue2_return(Metadata), Metadata) -> exec_return(Metadata) when Metadata :: term().
-callback send_message(stream(), continue2_simple(Message), Message) -> exec_simple() when Message :: term().
-callback recv_message(stream(), continue2_decode(Buffer, Result, Rest), Buffer) -> exec_decode(Result, Rest) when Buffer :: binary(), Result :: term(), Rest :: binary().
-callback send_trailing_metadata(stream(), continue2_simple(Metadata), Metadata) -> exec_simple() when Metadata :: term().
-callback recv_trailing_metadata(stream(), continue2_return(Metadata), Metadata) -> exec_return(Metadata) when Metadata :: term().
% -callback cancel_stream(stream(), continue1_simple()) -> exec_simple().
% -callback grpc_end_stream(stream(), continue1_simple()) -> exec_simple().
% -callback grpc_terminate(stream(), continue2_simple(Reason), Reason) -> exec_simple() when Reason :: term().

-optional_callbacks([accept_stream/3,
                     init_stream/3,
                     send_initial_metadata/3,
                     recv_initial_metadata/3,
                     send_message/3,
                     recv_message/3,
                     send_trailing_metadata/3,
                     recv_trailing_metadata/3]).

'__struct__'() ->
    #{'__struct__' => ?MODULE,
      accept_stream => [],
      init_stream => [],
      send_initial_metadata => [],
      recv_initial_metadata => [],
      send_message => [],
      recv_message => [],
      send_trailing_metadata => [],
      recv_trailing_metadata => []}.

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

%%

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

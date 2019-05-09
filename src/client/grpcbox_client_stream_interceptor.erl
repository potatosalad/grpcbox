-module(grpcbox_client_stream_interceptor).

-export(['__struct__'/0,
         '__struct__'/1,
         new/1,
         new_stream/7,
         send_msg/3,
         recv_msg/3]).

-include("grpcbox.hrl").

-type new_stream_ret() :: {ok, grpcbox_client_stream:t()} | {error, term()}.
-type send_msg_ret() :: ok.
-type recv_msg_ret() :: {ok, term()} | {error, term()}.

-type new_stream_fun() ::
        fun((ctx:t(), grpcbox_channel:t(), binary(), #grpcbox_def{}, map()) -> new_stream_ret()).
-type send_msg_fun() ::
        fun((grpcbox_client_stream:t(), term()) -> send_msg_ret()).
-type recv_msg_fun() ::
        fun((grpcbox_client_stream:t(), timeout()) -> recv_msg_ret()).

-type new_stream_cb() ::
        fun((ctx:t(), grpcbox_channel:t(), binary(), #grpcbox_def{}, new_stream_fun(), map()) -> new_stream_ret()).
-type send_msg_cb() ::
        fun((grpcbox_client_stream:t(), send_msg_fun(), term()) -> send_msg_ret()).
-type recv_msg_cb() ::
        fun((grpcbox_client_stream:t(), recv_msg_fun(), timeout()) -> recv_msg_ret()).

-type t() :: #{'__struct__' := ?MODULE,
               new_stream := new_stream_cb(),
               send_msg := send_msg_cb(),
               recv_msg := recv_msg_cb()}.

-export_type([new_stream_ret/0,
              send_msg_ret/0,
              recv_msg_ret/0,
              new_stream_cb/0,
              send_msg_cb/0,
              recv_msg_cb/0,
              t/0]).

-callback new_stream(ctx:t(), grpcbox_channel:t(), binary(), #grpcbox_def{}, new_stream_fun(), map()) -> new_stream_ret().
-callback send_msg(grpcbox_client_stream:t(), send_msg_fun(), term()) -> send_msg_ret().
-callback recv_msg(grpcbox_client_stream:t(), recv_msg_fun(), timeout()) -> recv_msg_ret().

-define(is_timeout(T), ((is_integer(T) andalso T >= 0) orelse T =:= infinity)).

-spec '__struct__'() -> t().
'__struct__'() ->
    #{'__struct__' => ?MODULE,
      new_stream => nil,
      send_msg => nil,
      recv_msg => nil}.

-spec '__struct__'(list() | map()) -> t().
'__struct__'(List) when is_list(List) ->
    '__struct__'(maps:from_list(List));
'__struct__'(Map) when is_map(Map) ->
    maps:fold(fun validate_and_update/3, '__struct__'(), maps:remove('__struct__', Map)).

-spec new(Interceptor) -> Interceptor when Interceptor :: t()
       ; ({Function, Arg}) -> Interceptor when Interceptor :: t(), Function :: function(), Arg :: term()
       ; (Module) -> Interceptor when Interceptor :: t(), Module :: module()
       ; (Map) -> Interceptor when Interceptor :: t(), Map :: map().
new(Interceptor=#{'__struct__' := ?MODULE}) ->
    Interceptor;
new({Function, Arg}) when is_function(Function, 1) ->
    new(Function(Arg));
new(Module) when is_atom(Module) ->
    new(#{new_stream => fun Module:new_stream/6,
          send_msg => fun Module:send_msg/3,
          recv_msg => fun Module:recv_msg/3});
new(Map=#{new_stream := _,
          send_msg := _,
          recv_msg := _}) ->
    '__struct__'(Map).

-spec new_stream(ctx:t(), grpcbox_channel:t(), t() | undefined, binary(), #grpcbox_def{}, new_stream_fun(), map()) -> new_stream_ret().
new_stream(Ctx, Channel, Interceptor, Path, Definition, NextFun, Options) when is_function(NextFun, 5) ->
    case Interceptor of
        undefined ->
            NextFun(Ctx, Channel, Path, Definition, Options);
        #{'__struct__' := ?MODULE, new_stream := NewStream} when is_function(NewStream, 6) ->
            case NewStream(Ctx, Channel, Path, Definition, NextFun, Options) of
                {ok, Stream0 = #{'__struct__' := grpcbox_client_stream}} ->
                    Stream = Stream0#{stream_interceptor := Interceptor},
                    {ok, Stream};
                Error = {error, _Reason} ->
                    Error
            end
    end.

-spec send_msg(grpcbox_client_stream:t(), send_msg_fun(), term()) -> send_msg_ret().
send_msg(Stream=#{stream_interceptor := #{send_msg := SendMsg}}, NextFun, Input) when is_function(NextFun, 2) ->
    SendMsg(Stream, NextFun, Input);
send_msg(Stream, NextFun, Input) when is_function(NextFun, 2) ->
    NextFun(Stream, Input).

-spec recv_msg(grpcbox_client_stream:t(), recv_msg_fun(), timeout()) -> recv_msg_ret().
recv_msg(Stream=#{stream_interceptor := #{recv_msg := RecvMsg}}, NextFun, Timeout) when is_function(NextFun, 2) andalso ?is_timeout(Timeout) ->
    RecvMsg(Stream, NextFun, Timeout);
recv_msg(Stream, NextFun, Timeout) when is_function(NextFun, 2) andalso ?is_timeout(Timeout) ->
    NextFun(Stream, Timeout).

%%

%% @private
validate_and_update(K=new_stream, V, S) when is_function(V, 6) ->
    maps:update(K, V, S);
validate_and_update(K=send_msg, V, S) when is_function(V, 3) ->
    maps:update(K, V, S);
validate_and_update(K=recv_msg, V, S) when is_function(V, 3) ->
    maps:update(K, V, S).

%%%-------------------------------------------------------------------
%% @doc Client module for grpc service grpc.lb.v1.LoadBalancer.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-04-22T18:03:35+00:00 and should not be modified manually

-module(grpcbox_load_balancer_client).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("grpcbox/include/grpcbox.hrl").

-define(is_ctx(Ctx), is_tuple(Ctx) andalso element(1, Ctx) =:= ctx).

-define(SERVICE, 'grpc.lb.v1.LoadBalancer').
-define(PROTO_MODULE, 'grpcbox_load_balancer_pb').
-define(MARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:encode_msg(I, T) end).
-define(UNMARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:decode_msg(I, T) end).
-define(DEF(Input, Output, MessageType), #grpcbox_def{service=?SERVICE,
                                                      message_type=MessageType,
                                                      marshal_fun=?MARSHAL_FUN(Input),
                                                      unmarshal_fun=?UNMARSHAL_FUN(Output)}).

%% @doc 
-spec balance_load() ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
balance_load() ->
    balance_load(ctx:new(), #{}).

-spec balance_load(ctx:t() | grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
balance_load(Ctx) when ?is_ctx(Ctx) ->
    balance_load(Ctx, #{});
balance_load(Options) ->
    balance_load(ctx:new(), Options).

-spec balance_load(ctx:t(), grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
balance_load(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.lb.v1.LoadBalancer/BalanceLoad">>, ?DEF(load_balance_request, load_balance_response, <<"grpc.lb.v1.LoadBalanceRequest">>), Options).


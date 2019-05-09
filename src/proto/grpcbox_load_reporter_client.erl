%%%-------------------------------------------------------------------
%% @doc Client module for grpc service grpc.lb.v1.LoadReporter.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-04-22T18:03:35+00:00 and should not be modified manually

-module(grpcbox_load_reporter_client).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("grpcbox/include/grpcbox.hrl").

-define(is_ctx(Ctx), is_tuple(Ctx) andalso element(1, Ctx) =:= ctx).

-define(SERVICE, 'grpc.lb.v1.LoadReporter').
-define(PROTO_MODULE, 'grpcbox_load_reporter_pb').
-define(MARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:encode_msg(I, T) end).
-define(UNMARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:decode_msg(I, T) end).
-define(DEF(Input, Output, MessageType), #grpcbox_def{service=?SERVICE,
                                                      message_type=MessageType,
                                                      marshal_fun=?MARSHAL_FUN(Input),
                                                      unmarshal_fun=?UNMARSHAL_FUN(Output)}).

%% @doc 
-spec report_load() ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
report_load() ->
    report_load(ctx:new(), #{}).

-spec report_load(ctx:t() | grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
report_load(Ctx) when ?is_ctx(Ctx) ->
    report_load(Ctx, #{});
report_load(Options) ->
    report_load(ctx:new(), Options).

-spec report_load(ctx:t(), grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
report_load(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.lb.v1.LoadReporter/ReportLoad">>, ?DEF(load_report_request, load_report_response, <<"grpc.lb.v1.LoadReportRequest">>), Options).


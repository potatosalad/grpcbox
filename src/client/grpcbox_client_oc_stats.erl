-module(grpcbox_client_oc_stats).

% -behaviour(grpcbox_client_interceptor).

%% grpcbox_client_interceptor callbacks
-export([grpc_init/3]).
-export([grpc_outbound_frame/3]).
-export([grpc_inbound_frame/3]).
% -export([grpc_end_stream/2]).
-export([grpc_terminate/3]).

%% Records
-record(stats, {
    recv_bytes = 0 :: non_neg_integer(),
    sent_bytes = 0 :: non_neg_integer(),
    recv_count = 0 :: non_neg_integer(),
    sent_count = 0 :: non_neg_integer(),
    begin_time = erlang:monotonic_time(millisecond) :: integer(),
    end_time = nil :: nil | integer()
}).

grpc_init(Stream0=#{ctx := Ctx0, env := Env0, method := Method}, NextFun, Options) ->
    Ctx1 = ctx:with_value(Ctx0, grpc_client_method, Method),
    Ctx2 = oc_tags:new(Ctx1, #{grpc_client_method => Method}),
    _ = oc_stat:record(Ctx2, 'grpc.io/client/started_rpcs', 1),
    Env1 = Env0#{?MODULE => #stats{}},
    Stream1 = Stream0#{ctx := Ctx2, env := Env1},
    NextFun(Stream1, Options).

grpc_outbound_frame(Stream0=#{env := #{?MODULE := #stats{}}}, NextFun, Data) ->
    case NextFun(Stream0, Data) of
        {ok, Result = {_, UncompressedSize, _}, Stream1=#{ctx := Ctx, env := Env0=#{?MODULE := Stats0=#stats{sent_bytes = SentBytes, sent_count = SentCount}}}} ->
            _ = oc_stat:record(Ctx, [{'grpc.io/client/sent_messages_per_method', 1},
                                     {'grpc.io/client/sent_bytes_per_method', UncompressedSize}]),
            Env1 = Env0#{?MODULE := Stats0#stats{sent_bytes = SentBytes + UncompressedSize, sent_count = SentCount + 1}},
            Stream2 = Stream1#{env := Env1},
            {ok, Result, Stream2}
    end.

grpc_inbound_frame(Stream0=#{env := #{?MODULE := #stats{}}}, NextFun, Data) ->
    case NextFun(Stream0, Data) of
        {ok, Result = {_, UncompressedSize, _}, Rest, Stream1=#{ctx := Ctx, env := Env0=#{?MODULE := Stats0=#stats{recv_bytes = RecvBytes, recv_count = RecvCount}}}} ->
            _ = oc_stat:record(Ctx, [{'grpc.io/client/received_messages_per_method', 1},
                                     {'grpc.io/client/received_bytes_per_method', UncompressedSize}]),
            Env1 = Env0#{?MODULE := Stats0#stats{recv_bytes = RecvBytes + UncompressedSize, recv_count = RecvCount + 1}},
            Stream2 = Stream1#{env := Env1},
            {ok, Result, Rest, Stream2};
        NeedsMore = {more, _} ->
            NeedsMore
    end.

% grpc_end_stream(Stream, Continue) ->
%     io:format("~s:~s~n", [?MODULE, grpc_end_stream]),
%     Continue(Stream).

grpc_terminate(Stream0=#{ctx := Ctx0, status := Status, env := Env0=#{?MODULE := Stats0=#stats{sent_bytes = SentBytes, sent_count = SentCount, recv_bytes = RecvBytes, recv_count = RecvCount, begin_time = BeginTime}}}, NextFun, Reason) ->
    Ctx1 = ctx:with_value(Ctx0, grpc_client_status, Status),
    Ctx2 = oc_tags:new(Ctx1, #{grpc_client_status => Status}),
    EndTime = erlang:monotonic_time(millisecond),
    _ = oc_stat:record(Ctx2, [{'grpc.io/client/sent_messages_per_rpc', SentCount},
                              {'grpc.io/client/sent_bytes_per_rpc', SentBytes},
                              {'grpc.io/client/received_messages_per_rpc', RecvCount},
                              {'grpc.io/client/received_bytes_per_rpc', RecvBytes},
                              {'grpc.io/client/roundtrip_latency', EndTime - BeginTime}]),
                              %% See: https://github.com/census-instrumentation/opencensus-specs/blob/2a9d2a76d6401ad530714c17daf812e04b92fcc4/stats/gRPC.md#how-is-the-server-latency-on-the-client-recorded-grcpioclientserver_latency
                              %% {'grpc.io/client/server_latency', ???}])
    Env1 = Env0#{?MODULE := Stats0#stats{end_time = EndTime}},
    Stream1 = Stream0#{ctx := Ctx2, env := Env1},
    NextFun(Stream1, Reason).

-module(grpcbox_client_oc_trace).

% -behaviour(grpcbox_client_interceptor).

%% grpcbox_client_interceptor callbacks
-export([grpc_init/3]).
-export([grpc_outbound_frame/3]).
-export([grpc_inbound_frame/3]).
% -export([grpc_end_stream/2]).
-export([grpc_terminate/3]).

%% Records
-record(trace, {
    recv_message_id = 1 :: pos_integer(),
    sent_message_id = 1 :: pos_integer()
}).

grpc_init(Stream0=#{ctx := Ctx0, env := Env0, method := Method}, NextFun, Options) ->
    Ctx1 = oc_trace:with_child_span(Ctx0, Method, #{kind => 'CLIENT'}),
    SpanCtx = oc_trace:current_span_ctx(Ctx1),
    case oc_trace:is_enabled(SpanCtx) of
        true ->
            Env1 = Env0#{?MODULE => #trace{}},
            TraceState = oc_propagation_binary:encode(SpanCtx),
            Ctx2 = grpcbox_metadata:append_to_outgoing_ctx(Ctx1, #{<<"grpc-trace-bin">> => TraceState}),
            Stream1 = Stream0#{ctx := Ctx2, env := Env1},
            NextFun(Stream1, Options);
        false ->
            Env1 = Env0#{?MODULE => false},
            Stream1 = Stream0#{ctx := Ctx1, env := Env1},
            NextFun(Stream1, Options)
    end.

grpc_outbound_frame(Stream=#{env := #{?MODULE := false}}, NextFun, Data) ->
    NextFun(Stream, Data);
grpc_outbound_frame(Stream0=#{env := #{?MODULE := #trace{}}}, NextFun, Data) ->
    case NextFun(Stream0, Data) of
        {ok, Result = {_, UncompressedSize, CompressedSize}, Stream1=#{ctx := Ctx, env := Env0=#{?MODULE := Trace0=#trace{sent_message_id = MessageId}}}} ->
            MessageEvent = oc_trace:message_event('SENT', MessageId, UncompressedSize, CompressedSize),
            SpanCtx = oc_trace:current_span_ctx(Ctx),
            _ = oc_trace:add_time_event(MessageEvent, SpanCtx),
            Env1 = Env0#{?MODULE := Trace0#trace{sent_message_id = MessageId + 1}},
            Stream2 = Stream1#{env := Env1},
            {ok, Result, Stream2}
    end.

grpc_inbound_frame(Stream=#{env := #{?MODULE := false}}, NextFun, Data) ->
    NextFun(Stream, Data);
grpc_inbound_frame(Stream0=#{env := #{?MODULE := #trace{}}}, NextFun, Data) ->
    case NextFun(Stream0, Data) of
        {ok, Result = {_, UncompressedSize, CompressedSize}, Rest, Stream1=#{ctx := Ctx, env := Env0=#{?MODULE := Trace0=#trace{recv_message_id = MessageId}}}} ->
            MessageEvent = oc_trace:message_event('RECV', MessageId, UncompressedSize, CompressedSize),
            SpanCtx = oc_trace:current_span_ctx(Ctx),
            _ = oc_trace:add_time_event(MessageEvent, SpanCtx),
            Env1 = Env0#{?MODULE := Trace0#trace{recv_message_id = MessageId + 1}},
            Stream2 = Stream1#{env := Env1},
            {ok, Result, Rest, Stream2};
        NeedsMore = {more, _} ->
            NeedsMore
    end.

% grpc_end_stream(Stream, Continue) ->
%     io:format("~s:~s~n", [?MODULE, grpc_end_stream]),
%     Continue(Stream).
%     % grpcbox_client_interceptor:next(Stream, Continue, []).

grpc_terminate(Stream=#{ctx := Ctx, status := Status, message := Message}, NextFun, Reason) ->
    SpanCtx = oc_trace:current_span_ctx(Ctx),
    _ = oc_trace:set_status(Status, Message, SpanCtx),
    _ = oc_trace:finish_span(SpanCtx),
    NextFun(Stream, Reason).

-module(grpcbox_client_debug).

-behaviour(grpcbox_client_interceptor).

-export([grpc_init/3,
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

-include_lib("kernel/include/logger.hrl").

-define(what(), iolist_to_binary([?MODULE_STRING, $:, atom_to_list(?FUNCTION_NAME)])).

grpc_init(Stream, Continue, Options) ->
    ?LOG_DEBUG(#{type => command, what => ?what(), stream => Stream, arguments => [Options]}),
    Result = Continue(Stream, Options),
    ?LOG_DEBUG(#{type => event, what => ?what(), result => Result}),
    Result.

grpc_send_headers(Stream, Continue, Headers) ->
    ?LOG_DEBUG(#{type => command, what => ?what(), stream => Stream, arguments => [Headers]}),
    Result = Continue(Stream, Headers),
    ?LOG_DEBUG(#{type => event, what => ?what(), result => Result}),
    Result.

grpc_recv_headers(Stream, Continue, Headers) ->
    ?LOG_DEBUG(#{type => command, what => ?what(), stream => Stream, arguments => [Headers]}),
    Result = Continue(Stream, Headers),
    ?LOG_DEBUG(#{type => event, what => ?what(), result => Result}),
    Result.

grpc_marshal_message(Stream, Continue, Message) ->
    ?LOG_DEBUG(#{type => command, what => ?what(), stream => Stream, arguments => [Message]}),
    Result = Continue(Stream, Message),
    ?LOG_DEBUG(#{type => event, what => ?what(), result => Result}),
    Result.

grpc_unmarshal_message(Stream, Continue, Message) ->
    ?LOG_DEBUG(#{type => command, what => ?what(), stream => Stream, arguments => [Message]}),
    Result = Continue(Stream, Message),
    ?LOG_DEBUG(#{type => event, what => ?what(), result => Result}),
    Result.

grpc_outbound_frame(Stream, Continue, Message) ->
    ?LOG_DEBUG(#{type => command, what => ?what(), stream => Stream, arguments => [Message]}),
    Result = Continue(Stream, Message),
    ?LOG_DEBUG(#{type => event, what => ?what(), result => Result}),
    Result.

grpc_inbound_frame(Stream, Continue, Buffer) ->
    ?LOG_DEBUG(#{type => command, what => ?what(), stream => Stream, arguments => [Buffer]}),
    Result = Continue(Stream, Buffer),
    ?LOG_DEBUG(#{type => event, what => ?what(), result => Result}),
    Result.

grpc_send_data(Stream, Continue, Message) ->
    ?LOG_DEBUG(#{type => command, what => ?what(), stream => Stream, arguments => [Message]}),
    Result = Continue(Stream, Message),
    ?LOG_DEBUG(#{type => event, what => ?what(), result => Result}),
    Result.

grpc_recv_data(Stream, Continue, Buffer) ->
    ?LOG_DEBUG(#{type => command, what => ?what(), stream => Stream, arguments => [Buffer]}),
    Result = Continue(Stream, Buffer),
    ?LOG_DEBUG(#{type => event, what => ?what(), result => Result}),
    Result.

grpc_recv_trailers(Stream, Continue, Trailers) ->
    ?LOG_DEBUG(#{type => command, what => ?what(), stream => Stream, arguments => [Trailers]}),
    Result = Continue(Stream, Trailers),
    ?LOG_DEBUG(#{type => event, what => ?what(), result => Result}),
    Result.

grpc_cancel(Stream, Continue) ->
    ?LOG_DEBUG(#{type => command, what => ?what(), stream => Stream, arguments => []}),
    Result = Continue(Stream),
    ?LOG_DEBUG(#{type => event, what => ?what(), result => Result}),
    Result.

grpc_end_stream(Stream, Continue) ->
    ?LOG_DEBUG(#{type => command, what => ?what(), stream => Stream, arguments => []}),
    Result = Continue(Stream),
    ?LOG_DEBUG(#{type => event, what => ?what(), result => Result}),
    Result.

grpc_terminate(Stream, Continue, Reason) ->
    ?LOG_DEBUG(#{type => command, what => ?what(), stream => Stream, arguments => [Reason]}),
    Result = Continue(Stream, Reason),
    ?LOG_DEBUG(#{type => event, what => ?what(), result => Result}),
    Result.

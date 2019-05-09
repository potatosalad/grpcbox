%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.channelz.v1.Channelz.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-04-19T15:17:14+00:00 and should not be modified manually

-module(grpcbox_channelz_bhvr).

%% @doc Unary RPC
-callback get_top_channels(ctx:ctx(), grpcbox_channelz_pb:get_top_channels_request()) ->
    {ok, grpcbox_channelz_pb:get_top_channels_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback get_servers(ctx:ctx(), grpcbox_channelz_pb:get_servers_request()) ->
    {ok, grpcbox_channelz_pb:get_servers_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback get_server(ctx:ctx(), grpcbox_channelz_pb:get_server_request()) ->
    {ok, grpcbox_channelz_pb:get_server_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback get_server_sockets(ctx:ctx(), grpcbox_channelz_pb:get_server_sockets_request()) ->
    {ok, grpcbox_channelz_pb:get_server_sockets_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback get_channel(ctx:ctx(), grpcbox_channelz_pb:get_channel_request()) ->
    {ok, grpcbox_channelz_pb:get_channel_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback get_subchannel(ctx:ctx(), grpcbox_channelz_pb:get_subchannel_request()) ->
    {ok, grpcbox_channelz_pb:get_subchannel_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback get_socket(ctx:ctx(), grpcbox_channelz_pb:get_socket_request()) ->
    {ok, grpcbox_channelz_pb:get_socket_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().


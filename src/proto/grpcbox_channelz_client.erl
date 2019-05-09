%%%-------------------------------------------------------------------
%% @doc Client module for grpc service grpc.channelz.v1.Channelz.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-04-19T15:17:14+00:00 and should not be modified manually

-module(grpcbox_channelz_client).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("grpcbox/include/grpcbox.hrl").

-define(is_ctx(Ctx), is_tuple(Ctx) andalso element(1, Ctx) =:= ctx).

-define(SERVICE, 'grpc.channelz.v1.Channelz').
-define(PROTO_MODULE, 'grpcbox_channelz_pb').
-define(MARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:encode_msg(I, T) end).
-define(UNMARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:decode_msg(I, T) end).
-define(DEF(Input, Output, MessageType), #grpcbox_def{service=?SERVICE,
                                                      message_type=MessageType,
                                                      marshal_fun=?MARSHAL_FUN(Input),
                                                      unmarshal_fun=?UNMARSHAL_FUN(Output)}).

%% @doc Unary RPC
-spec get_top_channels(grpcbox_channelz_pb:get_top_channels_request()) ->
    {ok, grpcbox_channelz_pb:get_top_channels_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_top_channels(Input) ->
    get_top_channels(ctx:new(), Input, #{}).

-spec get_top_channels(ctx:t() | grpcbox_channelz_pb:get_top_channels_request(), grpcbox_channelz_pb:get_top_channels_request() | grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_top_channels_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_top_channels(Ctx, Input) when ?is_ctx(Ctx) ->
    get_top_channels(Ctx, Input, #{});
get_top_channels(Input, Options) ->
    get_top_channels(ctx:new(), Input, Options).

-spec get_top_channels(ctx:t(), grpcbox_channelz_pb:get_top_channels_request(), grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_top_channels_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_top_channels(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.channelz.v1.Channelz/GetTopChannels">>, Input, ?DEF(get_top_channels_request, get_top_channels_response, <<"grpc.channelz.v1.GetTopChannelsRequest">>), Options).

%% @doc Unary RPC
-spec get_servers(grpcbox_channelz_pb:get_servers_request()) ->
    {ok, grpcbox_channelz_pb:get_servers_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_servers(Input) ->
    get_servers(ctx:new(), Input, #{}).

-spec get_servers(ctx:t() | grpcbox_channelz_pb:get_servers_request(), grpcbox_channelz_pb:get_servers_request() | grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_servers_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_servers(Ctx, Input) when ?is_ctx(Ctx) ->
    get_servers(Ctx, Input, #{});
get_servers(Input, Options) ->
    get_servers(ctx:new(), Input, Options).

-spec get_servers(ctx:t(), grpcbox_channelz_pb:get_servers_request(), grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_servers_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_servers(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.channelz.v1.Channelz/GetServers">>, Input, ?DEF(get_servers_request, get_servers_response, <<"grpc.channelz.v1.GetServersRequest">>), Options).

%% @doc Unary RPC
-spec get_server(grpcbox_channelz_pb:get_server_request()) ->
    {ok, grpcbox_channelz_pb:get_server_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_server(Input) ->
    get_server(ctx:new(), Input, #{}).

-spec get_server(ctx:t() | grpcbox_channelz_pb:get_server_request(), grpcbox_channelz_pb:get_server_request() | grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_server_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_server(Ctx, Input) when ?is_ctx(Ctx) ->
    get_server(Ctx, Input, #{});
get_server(Input, Options) ->
    get_server(ctx:new(), Input, Options).

-spec get_server(ctx:t(), grpcbox_channelz_pb:get_server_request(), grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_server_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_server(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.channelz.v1.Channelz/GetServer">>, Input, ?DEF(get_server_request, get_server_response, <<"grpc.channelz.v1.GetServerRequest">>), Options).

%% @doc Unary RPC
-spec get_server_sockets(grpcbox_channelz_pb:get_server_sockets_request()) ->
    {ok, grpcbox_channelz_pb:get_server_sockets_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_server_sockets(Input) ->
    get_server_sockets(ctx:new(), Input, #{}).

-spec get_server_sockets(ctx:t() | grpcbox_channelz_pb:get_server_sockets_request(), grpcbox_channelz_pb:get_server_sockets_request() | grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_server_sockets_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_server_sockets(Ctx, Input) when ?is_ctx(Ctx) ->
    get_server_sockets(Ctx, Input, #{});
get_server_sockets(Input, Options) ->
    get_server_sockets(ctx:new(), Input, Options).

-spec get_server_sockets(ctx:t(), grpcbox_channelz_pb:get_server_sockets_request(), grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_server_sockets_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_server_sockets(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.channelz.v1.Channelz/GetServerSockets">>, Input, ?DEF(get_server_sockets_request, get_server_sockets_response, <<"grpc.channelz.v1.GetServerSocketsRequest">>), Options).

%% @doc Unary RPC
-spec get_channel(grpcbox_channelz_pb:get_channel_request()) ->
    {ok, grpcbox_channelz_pb:get_channel_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_channel(Input) ->
    get_channel(ctx:new(), Input, #{}).

-spec get_channel(ctx:t() | grpcbox_channelz_pb:get_channel_request(), grpcbox_channelz_pb:get_channel_request() | grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_channel_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_channel(Ctx, Input) when ?is_ctx(Ctx) ->
    get_channel(Ctx, Input, #{});
get_channel(Input, Options) ->
    get_channel(ctx:new(), Input, Options).

-spec get_channel(ctx:t(), grpcbox_channelz_pb:get_channel_request(), grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_channel_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_channel(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.channelz.v1.Channelz/GetChannel">>, Input, ?DEF(get_channel_request, get_channel_response, <<"grpc.channelz.v1.GetChannelRequest">>), Options).

%% @doc Unary RPC
-spec get_subchannel(grpcbox_channelz_pb:get_subchannel_request()) ->
    {ok, grpcbox_channelz_pb:get_subchannel_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_subchannel(Input) ->
    get_subchannel(ctx:new(), Input, #{}).

-spec get_subchannel(ctx:t() | grpcbox_channelz_pb:get_subchannel_request(), grpcbox_channelz_pb:get_subchannel_request() | grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_subchannel_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_subchannel(Ctx, Input) when ?is_ctx(Ctx) ->
    get_subchannel(Ctx, Input, #{});
get_subchannel(Input, Options) ->
    get_subchannel(ctx:new(), Input, Options).

-spec get_subchannel(ctx:t(), grpcbox_channelz_pb:get_subchannel_request(), grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_subchannel_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_subchannel(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.channelz.v1.Channelz/GetSubchannel">>, Input, ?DEF(get_subchannel_request, get_subchannel_response, <<"grpc.channelz.v1.GetSubchannelRequest">>), Options).

%% @doc Unary RPC
-spec get_socket(grpcbox_channelz_pb:get_socket_request()) ->
    {ok, grpcbox_channelz_pb:get_socket_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_socket(Input) ->
    get_socket(ctx:new(), Input, #{}).

-spec get_socket(ctx:t() | grpcbox_channelz_pb:get_socket_request(), grpcbox_channelz_pb:get_socket_request() | grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_socket_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_socket(Ctx, Input) when ?is_ctx(Ctx) ->
    get_socket(Ctx, Input, #{});
get_socket(Input, Options) ->
    get_socket(ctx:new(), Input, Options).

-spec get_socket(ctx:t(), grpcbox_channelz_pb:get_socket_request(), grpcbox_client:options()) ->
    {ok, grpcbox_channelz_pb:get_socket_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_socket(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.channelz.v1.Channelz/GetSocket">>, Input, ?DEF(get_socket_request, get_socket_response, <<"grpc.channelz.v1.GetSocketRequest">>), Options).


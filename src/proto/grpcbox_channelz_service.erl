-module(grpcbox_channelz_service).

-include("grpcbox.hrl").

-behaviour(grpcbox_channelz_bhvr).

%% grpcbox_channelz_bhvr callbacks
-export([get_top_channels/2,
         get_servers/2,
         get_server/2,
         get_server_sockets/2,
         get_channel/2,
         get_subchannel/2,
         get_socket/2]).

%%%===================================================================
%%% grpcbox_channelz_bhvr callbacks
%%%===================================================================

-spec get_top_channels(ctx:ctx(), grpcbox_channelz_pb:get_top_channels_request()) ->
    {ok, grpcbox_channelz_pb:get_top_channels_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().
get_top_channels(Ctx, _GetTopChannelsRequest = #{start_channel_id := StartChannelId, max_results := MaxResults}) ->
    GetTopChannelsResponse = #{channel => [], 'end' => true},
    {ok, GetTopChannelsResponse, Ctx}.

-spec get_servers(ctx:ctx(), grpcbox_channelz_pb:get_servers_request()) ->
    {ok, grpcbox_channelz_pb:get_servers_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().
get_servers(Ctx, _GetServersRequest = #{start_server_id := StartServerId, max_results := MaxResults}) ->
    GetServersResponse = #{server => [], 'end' => true},
    {ok, GetServersResponse, Ctx}.

-spec get_server(ctx:ctx(), grpcbox_channelz_pb:get_server_request()) ->
    {ok, grpcbox_channelz_pb:get_server_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().
get_server(Ctx, _GetServerRequest = #{server_id := ServerId}) ->
    ServerRef = #{server_id => ServerId,
                  name => <<"myserver">>},
    ChannelTrace = #{num_events_logged => 0,
                     creation_timestamp => #{seconds => 0, nanos => 0},
                     events => []},
    ServerData = #{trace => ChannelTrace,
                   calls_started => 5,
                   calls_succeeded => 2,
                   calls_failed => 1,
                   last_call_started_timestamp => #{seconds => 0, nanos => 0}},
    SocketRef = #{socket_id => 1,
                  name => <<"mysocket">>},
    Server = #{ref => ServerRef,
               data => ServerData,
               listen_socket => [SocketRef]},
    GetServerResponse = #{server => Server},
    {ok, GetServerResponse, Ctx}.

-spec get_server_sockets(ctx:ctx(), grpcbox_channelz_pb:get_server_sockets_request()) ->
    {ok, grpcbox_channelz_pb:get_server_sockets_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().
get_server_sockets(Ctx, _GetServerSocketsRequest = #{server_id := ServerId, start_socket_id := StartSocketId, max_results := MaxResults}) ->
    GetServerSocketsResponse = #{socket_ref => [], 'end' => true},
    {ok, GetServerSocketsResponse, Ctx}.

-spec get_channel(ctx:ctx(), grpcbox_channelz_pb:get_channel_request()) ->
    {ok, grpcbox_channelz_pb:get_channel_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().
get_channel(_Ctx, _GetChannelRequest = #{channel_id := _ChannelId}) ->
    ?GRPC_ERROR(?GRPC_STATUS_NOT_FOUND, <<"Channel not found">>).

-spec get_subchannel(ctx:ctx(), grpcbox_channelz_pb:get_subchannel_request()) ->
    {ok, grpcbox_channelz_pb:get_subchannel_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().
get_subchannel(_Ctx, _GetSubchannelRequest = #{subchannel_id := _SubchannelId}) ->
    ?GRPC_ERROR(?GRPC_STATUS_NOT_FOUND, <<"Subchannel not found">>).

-spec get_socket(ctx:ctx(), grpcbox_channelz_pb:get_socket_request()) ->
    {ok, grpcbox_channelz_pb:get_socket_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().
get_socket(_Ctx, _GetSocketRequest = #{socket_id := _SocketId, summary := _Summary}) ->
    ?GRPC_ERROR(?GRPC_STATUS_NOT_FOUND, <<"Socket not found">>).

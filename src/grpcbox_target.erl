%%%-------------------------------------------------------------------
%% @doc grpcbox target API
%% See [https://github.com/grpc/grpc/blob/v1.20.0/doc/naming.md]
%% See [https://github.com/grpc/proposal/blob/master/A5-grpclb-in-dns.md]
%% See [https://github.com/grpc/proposal/blob/master/A14-channelz.md]
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_target).

-export(['__struct__'/0,
         '__struct__'/1]).

% -include("grpcbox.hrl").

% -type struct(Payload, EventType) :: #{
%     '__struct__' := ?MODULE,
%     payload := Payload,
%     event_type := EventType,
%     id => pos_integer(),
%     uncompressed_byte_size => non_neg_integer(),
%     compressed_byte_size => non_neg_integer()   
% }.

% -type recv(Payload) :: struct(Payload, 'RECV').
% -type recv() :: recv(term()).
% -type sent() :: struct(binary(), 'SENT').

% -export_type([sent/0,
%               recv/0,
%               recv/1]).

'__struct__'() ->
    #{'__struct__' => ?MODULE,
      host => nil,
      name => map(),
      protocol => nil,
      service_config => #{}}.

'__struct__'(List) when is_list(List) ->
    '__struct__'(maps:from_list(List));
'__struct__'(Map) when is_map(Map) ->
    maps:fold(fun maps:update/3, '__struct__'(), maps:without(['__struct__'], Map)).

% send_message(Stream=#{definition := #grpcbox_def{marshal_fun=MarshalFun}, encoding := Encoding, sent_message_id := MessageId}, Message) ->
%     UncompressedMessage = MarshalFun(Message),
%     {ok, {Payload, UncompressedByteSize, CompressedByteSize}} = grpcbox_frame:encode(UncompressedMessage, Encoding),
%     Struct = '__struct__'(#{payload => Payload,
%                             event_type => 'SENT',
%                             id => MessageId,
%                             uncompressed_byte_size => UncompressedByteSize,
%                             compressed_byte_size => CompressedByteSize}),
%     {ok, Struct, Stream#{sent_message_id := MessageId + 1}}.

% recv_message(Stream=#{definition := #grpcbox_def{unmarshal_fun=UnMarshalFun}, encoding := Encoding, recv_message_id := MessageId}, Buffer) ->
%     case grpcbox_frame:decode(Buffer, Encoding) of
%         {ok, {UncompressedMessage, UncompressedByteSize, CompressedByteSize}, Rest} ->
%             Payload = UnMarshalFun(UncompressedMessage),
%             Struct = '__struct__'(#{payload => Payload,
%                                     event_type => 'RECV',
%                                     id => MessageId,
%                                     uncompressed_byte_size => UncompressedByteSize,
%                                     compressed_byte_size => CompressedByteSize}),
%             {ok, Struct, Rest, Stream#{recv_message_id := MessageId + 1}};
%         {more, Rest} ->
%             {more, Rest, Stream}
%     end.

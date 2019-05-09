-module(grpcbox_frame).

-export([encode/2,
         decode/2,
         split/2]).

-include("grpcbox.hrl").

% coder(deflate) ->
%     {fun deflate_compress/1, fun deflate_uncompress/1};
% coder(gzip) ->
%     fun gzip_compress/1;
% coder(identity) ->
%     fun identity_compress/1;
% coder(snappy) ->
%     case snappy_detect() of
%         {ok, snappy} ->
%             fun snappy_compress/1;
%         {ok, snappyer} ->
%             fun snappyer_compress/1;
%         error ->
%             throw({error, {unknown_encoding, snappy}})
%     end;
% coder(Encoding) when is_atom(Encoding) ->
%     ?THROW(?GRPC_STATUS_UNIMPLEMENTED,
%            <<"Compression mechanism ", (atom_to_binary(Encoding, utf8))/binary,
%              " used for received frame not supported">>).

% encode(Uncompressed, identity) ->

% encode(Uncompressed, Encoding) when is_binary(Uncompressed) andalso is_atom(Encoding) ->
%     Compress = compress(Encoding),
%     encode(Uncompressed)

% encode(Message, )

encode(Uncompressed, deflate) when is_binary(Uncompressed) ->
    encode_compressed(Uncompressed, fun deflate_compress/1);
encode(Uncompressed, gzip) when is_binary(Uncompressed) ->
    encode_compressed(Uncompressed, fun gzip_compress/1);
encode(Uncompressed, identity) when is_binary(Uncompressed) ->
    UncompressedByteSize = byte_size(Uncompressed),
    Frame = <<0, UncompressedByteSize:32, Uncompressed/binary>>,
    {ok, {Frame, UncompressedByteSize, UncompressedByteSize}};
encode(Uncompressed, snappy) when is_binary(Uncompressed) ->
    encode_compressed(Uncompressed, fun snappy_compress/1);
encode(Uncompressed, Encoding) when is_binary(Uncompressed) andalso is_atom(Encoding) ->
    throw({error, {unknown_encoding, Encoding}}).

%% @private
encode_compressed(Uncompressed, Compress) when is_binary(Uncompressed) andalso is_function(Compress, 1) ->
    Compressed = Compress(Uncompressed),
    UncompressedByteSize = byte_size(Uncompressed),
    CompressedByteSize = byte_size(Compressed),
    Frame = <<1, CompressedByteSize:32, Compressed/binary>>,
    {ok, {Frame, UncompressedByteSize, CompressedByteSize}}.

% encode(deflate, Bin) ->
%     CompressedBin = deflate_compress(Bin),
%     Length = byte_size(CompressedBin),
%     <<1, Length:32, CompressedBin/binary>>;
% encode(gzip, Bin) ->
%     CompressedBin = gzip_compress(Bin),
%     Length = byte_size(CompressedBin),
%     <<1, Length:32, CompressedBin/binary>>;
% encode(identity, Bin) ->
%     Length = byte_size(Bin),
%     <<0, Length:32, Bin/binary>>;
% encode(snappy, Bin) ->
%     CompressedBin = snappy_compress(Bin),
%     Length = byte_size(CompressedBin),
%     <<1, Length:32, CompressedBin/binary>>;
% encode(Encoding, _) ->
%     throw({error, {unknown_encoding, Encoding}}).



% decode(<<0, UncompressedByteSize:32, Uncompressed:UncompressedByteSize/binary, Rest/binary>>, Encoding) when is_atom()

decode(<<0, UncompressedByteSize:32, Uncompressed:UncompressedByteSize/binary, Rest/binary>>, Encoding) when is_atom(Encoding) ->
    {ok, {Uncompressed, UncompressedByteSize, UncompressedByteSize}, Rest};
decode(<<1, CompressedByteSize:32, Compressed:CompressedByteSize/binary, Rest/binary>>, Encoding) when is_atom(Encoding) ->
    Uncompress = case Encoding of
                     deflate -> fun deflate_uncompress/1;
                     gzip -> fun gzip_uncompress/1;
                     snappy -> fun snappy_uncompress/1;
                     _ ->
                         ?THROW(?GRPC_STATUS_UNIMPLEMENTED,
                                <<"Compression mechanism ", (atom_to_binary(Encoding, utf8))/binary,
                                  " used for received frame not supported">>)
                 end,
    Uncompressed = try Uncompress(Compressed)
                   catch
                       error:data_error ->
                           ?THROW(?GRPC_STATUS_INTERNAL,
                                  <<"Could not decompress but compression algorithm ",
                                    (atom_to_binary(Encoding, utf8))/binary, " is supported">>)
                   end,
    UncompressedByteSize = byte_size(Uncompressed),
    {ok, {Uncompressed, UncompressedByteSize, CompressedByteSize}, Rest};
decode(Rest, Encoding) when is_binary(Rest) andalso is_atom(Encoding) ->
    {more, Rest}.

split(Frame, Encoding) ->
    split(Frame, Encoding, []).

%% @private
split(<<>>, _Encoding, Acc) ->
    {<<>>, lists:reverse(Acc)};
split(<<0, Length:32, Encoded:Length/binary, Rest/binary>>, Encoding, Acc) ->
    split(Rest, Encoding, [Encoded | Acc]);
split(<<1, Length:32, Compressed:Length/binary, Rest/binary>>, Encoding, Acc) ->
    Uncompress = case Encoding of
                     deflate -> fun deflate_uncompress/1;
                     gzip -> fun gzip_uncompress/1;
                     snappy -> fun snappy_uncompress/1;
                     _ ->
                         ?THROW(?GRPC_STATUS_UNIMPLEMENTED,
                                <<"Compression mechanism ", (atom_to_binary(Encoding, utf8))/binary,
                                  " used for received frame not supported">>)
                 end,
    Encoded = try Uncompress(Compressed)
              catch
                  error:data_error ->
                      ?THROW(?GRPC_STATUS_INTERNAL,
                             <<"Could not decompress but compression algorithm ",
                               (atom_to_binary(Encoding, utf8))/binary, " is supported">>)
              end,
    split(Rest, Encoding, [Encoded | Acc]);
split(Bin, _Encoding, Acc) ->
    {Bin, lists:reverse(Acc)}.

%%

%% @private
deflate_compress(Uncompressed) ->
    Z = zlib:open(),
    ok = zlib:deflateInit(Z, default, deflated, -15, 8, default),
    Compressed = zlib:deflate(Z, Uncompressed, finish),
    ok = zlib:deflateEnd(Z),
    ok = zlib:close(Z),
    erlang:iolist_to_binary(Compressed).

%% @private
deflate_uncompress(Compressed) ->
    Z = zlib:open(),
    ok = zlib:inflateInit(Z, -15),
    Uncompressed = zlib:inflate(Z, Compressed),
    ok = zlib:inflateEnd(Z),
    ok = zlib:close(Z),
    erlang:iolist_to_binary(Uncompressed).

%% @private
gzip_compress(Uncompressed) ->
    zlib:gzip(Uncompressed).

%% @private
gzip_uncompress(Compressed) ->
    zlib:gunzip(Compressed).

% %% @private
% identity_compress(Uncompressed) ->
%     Uncompressed.

% %% @private
% identity_uncompress(Compressed) ->
%     Compressed.

%% @private
snappy_compress(Uncompressed) ->
    case snappy_module() of
        {ok, Module} ->
            {ok, Uncompressed} = Module:compress(Uncompressed),
            Uncompressed;
        error ->
            throw({error, {unknown_encoding, snappy}})
    end.

%% @private
snappy_module() ->
    snappy_module([snappy, snappyer]).

%% @private
snappy_module([Module | Modules]) ->
    _ = code:ensure_loaded(Module),
    case {erlang:function_exported(Module, compress, 1),
          erlang:function_exported(Module, decompress, 1)} of
        {true,
         true} ->
            {ok, Module};
        _ ->
            snappy_module(Modules)
    end;
snappy_module([]) ->
    error.

%% @private
snappy_uncompress(Compressed) ->
    case snappy_module() of
        {ok, Module} ->
            {ok, Uncompressed} = Module:decompress(Compressed),
            Uncompressed;
        error ->
            Encoding = snappy,
            ?THROW(?GRPC_STATUS_UNIMPLEMENTED,
                   <<"Compression mechanism ", (atom_to_binary(Encoding, utf8))/binary,
                     " used for received frame not supported">>)
    end.

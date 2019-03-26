-module(grpcbox_frame).

-export([encode/2,
         split/2]).

-include("grpcbox.hrl").

encode(deflate, Bin) ->
    CompressedBin = deflate_compress(Bin),
    Length = byte_size(CompressedBin),
    <<1, Length:32, CompressedBin/binary>>;
encode(gzip, Bin) ->
    CompressedBin = gzip_compress(Bin),
    Length = byte_size(CompressedBin),
    <<1, Length:32, CompressedBin/binary>>;
encode(identity, Bin) ->
    Length = byte_size(Bin),
    <<0, Length:32, Bin/binary>>;
encode(snappy, Bin) ->
    CompressedBin = snappy_compress(Bin),
    Length = byte_size(CompressedBin),
    <<1, Length:32, CompressedBin/binary>>;
encode(Encoding, _) ->
    throw({error, {unknown_encoding, Encoding}}).

split(Frame, Encoding) ->
    split(Frame, Encoding, []).

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

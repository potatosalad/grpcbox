%%%-------------------------------------------------------------------
%% @doc grpcbox name resolver API
%% See [https://github.com/grpc/grpc/blob/v1.20.0/doc/naming.md]
%% See [https://github.com/grpc/grpc/issues/12295]
%% See [https://github.com/grpc/grpc/blob/v1.20.0/test/cpp/naming/resolver_test_record_groups.yaml]
%% See [https://github.com/grpc/grpc/blob/v1.20.0/src/core/ext/filters/client_channel/resolver/dns/c_ares/grpc_ares_wrapper.cc]
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_name_resolver).

-include_lib("kernel/src/inet_dns.hrl").

-export([parse/1]).
-export([parse/2]).
-export([resolve/1]).
-export([resolve/2]).

%% dns:host:port
%% dns://authority/host:port
%% ipv4:address1:port1,address

%% dns:///localhost
%% ipv4:///127.0.0.1

-define(DEFAULT_PORT, 443).

-define(is_digit(C), ($0 =< C andalso C =< $9)).
-define(is_hex(C), (($a =< C andalso C =< $f) orelse ($A =< C andalso C =< $F))).
-define(is_hex_digit(C), (?is_digit(C) orelse ?is_hex(C))).

parse(Name) ->
    parse(Name, ?DEFAULT_PORT).

parse(<<"dns:", Rest/binary>>, DefaultPort) ->
    [parse_dns(Rest, DefaultPort)];
parse(<<"ipv4:", Rest/binary>>, DefaultPort) ->
    [parse_ipv4(Source, DefaultPort) || Source <- binary:split(Rest, <<",">>, [global, trim_all])];
parse(<<"ipv6:", Rest/binary>>, DefaultPort) ->
    [parse_ipv6(Source, DefaultPort) || Source <- binary:split(Rest, <<",">>, [global, trim_all])];
parse(<<"unix:", Source/binary>>, _DefaultPort) ->
    [parse_unix(Source)];
parse(Source, DefaultPort) when is_list(Source) ->
    parse(unicode:characters_to_binary(Source), DefaultPort);
parse(Source, DefaultPort) when is_binary(Source) ->
    case uri_string:parse(Source) of
        URI = #{port := _} ->
            [URI];
        URI ->
            [maps:put(port, DefaultPort, URI)]
    end.

resolve(Name) ->
    resolve(Name, #{port => ?DEFAULT_PORT}).

resolve(Names = [#{scheme := _} | _], Config) ->
    resolve_endpoints(Names, Config, []);
resolve(Name, Config) when is_binary(Name) orelse is_list(Name) ->
    DefaultPort = maps:get(port, Config, ?DEFAULT_PORT),
    resolve(parse(Name, DefaultPort), Config).

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @private
coerce_ipv4(Address) ->
    case inet_parse:ipv4_address(unicode:characters_to_list(Address)) of
        {ok, Ipv4Address} ->
            Ipv4Address;
        {error, Reason} ->
            erlang:error(Reason, [Address])
    end.

%% @private
coerce_ipv6(Address) ->
    case inet_parse:ipv6_address(unicode:characters_to_list(Address)) of
        {ok, Ipv6Address} ->
            Ipv6Address;
        {error, Reason} ->
            erlang:error(Reason, [Address])
    end.

%% @private
parse_dns(<<"//", Rest/binary>>, DefaultPort) ->
    case binary:split(Rest, <<"/">>) of
        [Authority, Source] ->
            ParsedAuthority = parse_dns_authority(Authority),
            case binary:split(Source, <<":">>) of
                [Host, Port] ->
                    #{scheme => <<"dns">>, authority => ParsedAuthority, host => Host, port => binary_to_integer(Port)};
                [Host] ->
                    #{scheme => <<"dns">>, authority => ParsedAuthority, host => Host, port => DefaultPort}
            end
    end;
parse_dns(Source, DefaultPort) ->
    case binary:split(Source, <<":">>) of
        [Host, Port] ->
            #{scheme => <<"dns">>, host => Host, port => binary_to_integer(Port)};
        [Host] ->
            #{scheme => <<"dns">>, host => Host, port => DefaultPort}
    end.

%% @private
parse_dns_authority(Source = <<$[, _/binary>>) ->
    #{address := Address, port := Port} = parse_ipv6(Source, 53),
    {Address, Port};
parse_dns_authority(Source) ->
    case binary:match(Source, <<".">>) of
        nomatch ->
            #{address := Address, port := Port} = parse_ipv6(Source, 53),
            {Address, Port};
        {_, _} ->
            #{address := Address, port := Port} = parse_ipv4(Source, 53),
            {Address, Port}
    end.

%% @private
parse_ipv4(Source, DefaultPort) ->
    case binary:split(Source, <<":">>) of
        [Address, Port] ->
            #{scheme => <<"ipv4">>, address => coerce_ipv4(Address), port => binary_to_integer(Port)};
        [Address] ->
            #{scheme => <<"ipv4">>, address => coerce_ipv4(Address), port => DefaultPort}
    end.

%% @private
parse_ipv6(Source, DefaultPort) ->
    case parse_ipv6_address(Source, <<>>) of
        {Address, <<$:, Port/binary>>} ->
            #{scheme => <<"ipv6">>, address => coerce_ipv6(Address), port => binary_to_integer(Port)};
        {Address, <<>>} ->
            #{scheme => <<"ipv6">>, address => coerce_ipv6(Address), port => DefaultPort}
    end.

%% @private
parse_ipv6_address(<<$[, Source/binary>>, <<>>) ->
    case binary:split(Source, <<$]>>) of
        [Address, Rest] ->
            {ParsedAddress, <<>>} = parse_ipv6_address(Address, <<>>),
            {ParsedAddress, Rest}
    end;
parse_ipv6_address(<<C, Rest/binary>>, Acc) when ?is_hex_digit(C) orelse C =:= $: ->
    parse_ipv6_address(Rest, <<Acc/binary, C>>);
parse_ipv6_address(<<>>, Acc) ->
    {Acc, <<>>}.

%% @private
parse_unix(<<"//", AbsolutePath/binary>>) ->
    #{scheme => <<"unix">>, path => AbsolutePath};
parse_unix(Path) ->
    #{scheme => <<"unix">>, path => Path}.

%% @private
resolve_endpoints([Name | Names], Config, Acc) ->
    resolve_endpoints(Names, Config, resolve_endpoint(Name, Config, Acc));
resolve_endpoints([], _Config, Acc) ->
    lists:reverse(Acc).

%% @private
resolve_endpoint(Name = #{scheme := <<"ipv4">>, address := {_, _, _, _}, port := _}, _Config, Acc) ->
    [Name | Acc];
resolve_endpoint(Name = #{scheme := <<"ipv6">>, address := {_, _, _, _, _, _, _, _}, port := _}, _Config, Acc) ->
    [Name | Acc];
resolve_endpoint(Name = #{scheme := <<"unix">>, path := _}, _Config, Acc) ->
    [Name | Acc];
resolve_endpoint(Name = #{scheme := <<"dns">>, host := Host, port := Port}, Config, Acc) ->
    ResolveOptions = maps:get(resolve_options, Config, []),
    Options =
        case Name of
            #{authority := Nameserver = {_, _}} ->
                [{nameservers, [Nameserver]} | ResolveOptions];
            _ ->
                ResolveOptions
        end,
    HostString = unicode:characters_to_list(Host),
    ServiceConfig =
        case inet_res:resolve("_grpc_config." ++ HostString, in, txt, Options) of
            {ok, #dns_rec{anlist=[#dns_rr{type=txt, class=in, data=["grpc_config=" ++ GrpcConfig]} | _]}} ->
                unicode:characters_to_binary(GrpcConfig);
            _ ->
                nil
        end,
    Services =
        case inet_res:resolve("_grpclb._tcp." ++ HostString, in, srv, Options) of
            {ok, #dns_rec{anlist=SRVlist=[#dns_rr{type=srv, class=in} | _]}} ->
                resolve_srv_list(SRVlist, []);
            _ ->
                [{0, 0, Port, HostString}]
        end,
    resolve_services(Services, Options, ServiceConfig, Acc).

%% @private
resolve_a_list([#dns_rr{type=a, class=in, data=Address={_, _, _, _}} | Rest], Base, Acc) ->
    Name = Base#{scheme => <<"ipv4">>, address => Address},
    resolve_a_list(Rest, Base, [Name | Acc]);
resolve_a_list([], _Base, Acc) ->
    Acc.

%% @private
resolve_aaaa_list([#dns_rr{type=aaaa, class=in, data=Address={_, _, _, _, _, _, _, _}} | Rest], Base, Acc) ->
    Name = Base#{scheme => <<"ipv6">>, address => Address},
    resolve_aaaa_list(Rest, Base, [Name | Acc]);
resolve_aaaa_list([], _Base, Acc) ->
    Acc.

%% @private
resolve_srv_list([#dns_rr{type=srv, class=in, data={Priority, Weight, Port, Host}} | Rest], Acc) ->
    resolve_srv_list(Rest, [{Priority, Weight, Port, Host} | Acc]);
resolve_srv_list([], Acc) ->
    Acc.

%% @private
resolve_services([{Priority, Weight, Port, Host} | Rest], Options, ServiceConfig, Acc0) ->
    Base = #{host => unicode:characters_to_binary(Host),
             port => Port,
             priority => Priority,
             weight => Weight,
             service_config => ServiceConfig},
    Acc1 =
        case inet_res:resolve(Host, in, a, Options) of
            {ok, #dns_rec{anlist=Alist=[#dns_rr{type=a, class=in} | _]}} ->
                resolve_a_list(Alist, Base, Acc0);
            _ ->
                Acc0
        end,
    Acc2 =
        case inet_res:resolve(Host, in, aaaa, Options) of
            {ok, #dns_rec{anlist=AAAAlist=[#dns_rr{type=aaaa, class=in} | _]}} ->
                resolve_aaaa_list(AAAAlist, Base, Acc1);
            _ ->
                Acc1
        end,
    resolve_services(Rest, Options, ServiceConfig, Acc2);
resolve_services([], _Options, _ServiceConfig, Acc) ->
    Acc.

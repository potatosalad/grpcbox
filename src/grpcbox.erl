%%%-------------------------------------------------------------------
%% @doc grpc client
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox).

-export([start_server/1,
         server_child_spec/5,
         user_agent/0]).

-include_lib("chatterbox/include/http2.hrl").

-type encoding() :: identity | gzip | deflate | snappy | atom().
-type metadata() :: #{headers := grpcbox_metadata:t(),
                      trailers := grpcbox_metadata:t()}.

-type server_opts() :: #{server_opts => settings(), %% TODO: change this in chatterbox to be under a module
                         grpc_opts => #{service_protos := [module()]},
                         listen_opts => #{port => inet:port_number(),
                                          ip => inet:ip_address(),
                                          socket_options => [gen_tcp:option()]},
                         pool_opts => #{size => integer()},
                         transport_opts => #{ssl => boolean(),
                                             keyfile => file:filename_all(),
                                             certfile => file:filename_all(),
                                             cacertfile => file:filename_all()}}.

-export_type([metadata/0,
              server_opts/0,
              encoding/0]).

-spec start_server(server_opts()) -> supervisor:startchild_ret().
start_server(Opts) ->
    grpcbox_services_simple_sup:start_child(Opts).

server_child_spec(ServerOpts, GrpcOpts, ListenOpts, PoolOpts, TransportOpts) ->
    #{id => grpcbox_services_sup,
      start => {grpcbox_services_sup, start_link, [ServerOpts, GrpcOpts, ListenOpts,
                                                   PoolOpts, TransportOpts]},
      type => supervisor,
      restart => permanent,
      shutdown => 1000}.

-spec user_agent() -> binary().
user_agent() ->
    case erlang:function_exported(persistent_term, get, 2) of
        true ->
            case persistent_term:get('$grpcbox_user_agent', undefined) of
                UserAgent when is_binary(UserAgent) ->
                    UserAgent;
                undefined ->
                    ok = persistent_term:put('$grpcbox_user_agent', generate_user_agent()),
                    user_agent()
            end;
        false ->
            generate_user_agent()
    end.

%%

%% @private
generate_user_agent() ->
    _ = application:load(?MODULE),
    {ok, Version} = application:get_key(?MODULE, vsn),
    SystemArchitecture = erlang:system_info(system_architecture),
    OTPRelease = otp_release_version(),
    SystemVersion = erlang:system_info(version),
    [{_, _, OpenSSL} | _] = crypto:info_lib(),
    _ = application:load(chatterbox),
    {ok, ChatterboxVersion} = application:get_key(chatterbox, vsn),
    case maybe_elixir_version() of
        {ok, ElixirVersion} ->
            erlang:iolist_to_binary(io_lib:format(
                                      "grpc-erlang-grpcbox/~s "
                                      "(~s; ~s; elixir/~s; erlang/~s; erts/~s; chatterbox/~s)",
                                      [Version, SystemArchitecture, OpenSSL, ElixirVersion,
                                       OTPRelease, SystemVersion, ChatterboxVersion]));
        error ->
            erlang:iolist_to_binary(io_lib:format(
                                      "grpc-erlang-grpcbox/~s "
                                      "(~s; ~s; erlang/~s; erts/~s; chatterbox/~s)",
                                      [Version, SystemArchitecture, OpenSSL, OTPRelease,
                                       SystemVersion, ChatterboxVersion]))
    end.

%% @private
maybe_elixir_version() ->
    _ = code:ensure_loaded('Elixir.System'),
    case erlang:function_exported('Elixir.System', version, 0) of
        true ->
            try 'Elixir.System':version() of
                Version when is_binary(Version) ->
                    {ok, Version};
                _ ->
                    error
            catch
                _:_ ->
                    error
            end;
        false ->
            error
    end.

%% @private
otp_release_version() ->
    OTPRelease = erlang:system_info(otp_release),
    try file:read_file(filename:join([code:root_dir(), "releases", OTPRelease, "OTP_VERSION"])) of
        {ok, Version} ->
            VersionBinary = erlang:iolist_to_binary(Version),
            VersionStripped = binary:split(VersionBinary, [<<$\r>>, <<$\n>>], [global, trim_all]),
            erlang:iolist_to_binary(VersionStripped);
        {error, _Reason} ->
            erlang:iolist_to_binary(OTPRelease)
    catch
        _:_ ->
            erlang:iolist_to_binary(OTPRelease)
    end.

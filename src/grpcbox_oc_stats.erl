-module(grpcbox_oc_stats).

-export([register_measures/0,
         register_measures/1,
         subscribe_views/0,
         default_views/0,
         default_views/1,
         extra_views/0,
         extra_views/1]).

%% grpc_client_method   Full gRPC method name, including package, service and method,
%%                      e.g. google.bigtable.v2.Bigtable/CheckAndMutateRow
%% grpc_client_status   gRPC server status code received, e.g. OK, CANCELLED, DEADLINE_EXCEEDED

%% grpc_server_method   Full gRPC method name, including package, service and method,
%%                       e.g. com.exampleapi.v4.BookshelfService/Checkout
%% grpc_server_status   gRPC server status code returned, e.g. OK, CANCELLED, DEADLINE_EXCEEDED

register_measures() ->
    register_measures(client),
    register_measures(server).

-spec register_measures(client | server) -> ok.
register_measures(Type) ->
    [oc_stat_measure:new(Name, Desc, Unit) || {Name, Desc, Unit} <- register_measures_(Type)],
    ok.

register_measures_(client) ->
    [{'grpc.io/client/sent_messages_per_rpc',
      "Number of messages sent in each RPC (always 1 for non-streaming RPCs).",
      none},
     {'grpc.io/client/sent_bytes_per_rpc',
      "Total bytes sent in across all request messages per RPC.",
      bytes},
     {'grpc.io/client/received_messages_per_rpc',
      "Number of response messages received per RPC (always 1 for non-streaming RPCs).",
      none},
     {'grpc.io/client/received_bytes_per_rpc',
      "Total bytes received across all response messages per RPC.",
      bytes},
     {'grpc.io/client/roundtrip_latency',
      "Time between first byte of request sent to last byte of response received, or terminal error.",
      milli_seconds},
     {'grpc.io/client/server_latency',
      "Propagated from the server and should have the same value as grpc.io/server/latency.",
      milli_seconds},
     {'grpc.io/client/started_rpcs',
      "The total number of client RPCs ever opened, including those that have not completed.",
      none},
     {'grpc.io/client/sent_messages_per_method',
      "Total messages sent per method.",
      none},
     {'grpc.io/client/received_messages_per_method',
      "Total messages received per method.",
      none},
     {'grpc.io/client/sent_bytes_per_method',
      "Total bytes sent per method, recorded real-time as bytes are sent.",
      bytes},
     {'grpc.io/client/received_bytes_per_method',
      "Total bytes received per method, recorded real-time as bytes are received.",
      bytes}];
register_measures_(server) ->
    [{'grpc.io/server/received_messages_per_rpc',
      "Number of messages received in each RPC. Has value 1 for non-streaming RPCs.",
      none},
     {'grpc.io/server/received_bytes_per_rpc',
      "Total bytes received across all messages per RPC.",
      bytes},
     {'grpc.io/server/sent_messages_per_rpc',
      "Number of messages sent in each RPC. Has value 1 for non-streaming RPCs.",
      none},
     {'grpc.io/server/sent_bytes_per_rpc',
      "Total bytes sent in across all response messages per RPC.",
      bytes},
     {'grpc.io/server/server_latency',
      "Time between first byte of request received to last byte of response sent, or terminal error.",
      milli_seconds},
     {'grpc.io/server/started_rpcs',
      "The total number of server RPCs ever opened, including those that have not completed.",
      none}].

subscribe_views() ->
    [oc_stat_view:subscribe(V) || V <- default_views()].

default_views() ->
    default_views(client) ++ default_views(server).

default_views(client) ->
    [#{name => "grpc.io/client/sent_bytes_per_rpc",
       description => "Distribution of total bytes sent per RPC",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/sent_bytes_per_rpc',
       aggregation => default_size_distribution()},
     #{name => "grpc.io/client/received_bytes_per_rpc",
       description => "Distribution of total bytes received per RPC",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/received_bytes_per_rpc',
       aggregation => default_size_distribution()},
     #{name => "grpc.io/client/roundtrip_latency",
       description => "Distribution of time taken by request.",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/roundtrip_latency',
       aggregation => default_latency_distribution()},
     #{name => "grpc.io/client/completed_rpcs",
       description => "Total count of completed rpcs",
       tags => [grpc_client_method, grpc_client_status],
       measure => 'grpc.io/client/roundtrip_latency',
       aggregation => oc_stat_aggregation_count},
     #{name => "grpc.io/client/started_rpcs",
       description => "The total number of client RPCs ever opened, including those that have not completed.",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/started_rpcs',
       aggregation => oc_stat_aggregation_count}];
default_views(server) ->
    [#{name => "grpc.io/server/received_bytes_per_rpc",
       description => "Distribution of total bytes received per RPC",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/received_bytes_per_rpc',
       aggregation => default_size_distribution()},
     #{name => "grpc.io/server/sent_bytes_per_rpc",
       description => "Distribution of total bytes sent per RPC",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/sent_bytes_per_rpc',
       aggregation => default_size_distribution()},
     #{name => "grpc.io/server/server_latency",
       description => "Distribution of time taken by request.",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/server_latency',
       aggregation => default_latency_distribution()},
     #{name => "grpc.io/server/completed_rpcs",
       description => "Total count of completed rpcs",
       tags => [grpc_server_method, grpc_server_status],
       measure => 'grpc.io/server/server_latency',
       aggregation => oc_stat_aggregation_count},
     #{name => "grpc.io/server/started_rpcs",
       description => "The total number of server RPCs ever opened, including those that have not completed.",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/started_rpcs',
       aggregation => oc_stat_aggregation_count}].

extra_views() ->
    extra_views(client),
    extra_views(server).

extra_views(client) ->
    [#{name => "grpc.io/client/sent_messages_per_rpc",
       description => "Distribution of messages sent per RPC",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/sent_messages_per_rpc',
       aggregation => default_size_distribution()},
     #{name => "grpc.io/client/received_messages_per_rpc",
       description => "Distribution of messages received per RPC",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/received_messages_per_rpc',
       aggregation => default_latency_distribution()},
     #{name => "grpc.io/client/server_latency",
       description => "Distribution of latency value propagated from the server.",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/server_latency',
       aggregation => default_latency_distribution()},
     #{name => "grpc.io/client/sent_messages_per_method",
       description => "Total messages sent per method.",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/sent_messages_per_method',
       aggregation => oc_stat_aggregation_count},
     #{name => "grpc.io/client/sent_bytes_per_method",
       description => "Distribution of total bytes sent per method",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/sent_bytes_per_method',
       aggregation => oc_stat_aggregation_sum},
     #{name => "grpc.io/client/received_bytes_per_method",
       description => "Distribution of total bytes received per method",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/received_bytes_per_method',
       aggregation => oc_stat_aggregation_sum}];
extra_views(server) ->
    [#{name => "grpc.io/server/received_messages_per_rpc",
       description => "Distribution of messages received per RPC",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/received_messages_per_rpc',
       aggregation => default_latency_distribution()},
     #{name => "grpc.io/server/sent_messages_per_rpc",
       description => "Distribution of messages sent per RPC",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/sent_messages_per_rpc',
       aggregation => default_size_distribution()}].

default_size_distribution() ->
    {oc_stat_aggregation_distribution, [{buckets, [0, 1024, 2048, 4096, 16384, 65536,
                                                   262144, 1048576, 4194304, 16777216,
                                                   67108864, 268435456, 1073741824,
                                                   4294967296]}]}.

default_latency_distribution() ->
    {oc_stat_aggregation_distribution, [{buckets, [0, 1, 2, 3, 4, 5, 6, 8, 10, 13, 16, 20, 25, 30,
                                                   40, 50, 65, 80, 100, 130, 160, 200, 250, 300, 400,
                                                   500, 650, 800, 1000, 2000, 5000, 10000, 20000, 50000,
                                                   100000]}]}.

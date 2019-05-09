-ifndef(GRPCBOX_CHANNELZ_HRL).

-record(channelz_node_ctx, {
    node_id = 0 :: non_neg_integer(),
    type = nil :: nil | atom(),
    stats_enabled = false :: boolean(),
    trace_enabled = false :: boolean()
}).

-define(GRPCBOX_CHANNELZ_HRL, 1).

-endif.
-module(grpcbox_status).

-export([encode/1,
         decode/1]).

-include("grpcbox.hrl").

-type code() :: ok
              | cancelled
              | unknown
              | invalid_argument
              | deadline_exceeded
              | not_found
              | already_exists
              | permission_denied
              | resource_exhausted
              | failed_precondition
              | aborted
              | out_of_range
              | unimplemented
              | internal
              | unavailable
              | data_loss
              | unauthenticated.

-export_type([code/0]).

-spec encode(code()) -> binary().
encode(ok) -> ?GRPC_STATUS_OK;
encode(cancelled) -> ?GRPC_STATUS_CANCELLED;
encode(unknown) -> ?GRPC_STATUS_UNKNOWN;
encode(invalid_argument) -> ?GRPC_STATUS_INVALID_ARGUMENT;
encode(deadline_exceeded) -> ?GRPC_STATUS_DEADLINE_EXCEEDED;
encode(not_found) -> ?GRPC_STATUS_NOT_FOUND;
encode(already_exists) -> ?GRPC_STATUS_ALREADY_EXISTS ;
encode(permission_denied) -> ?GRPC_STATUS_PERMISSION_DENIED;
encode(resource_exhausted) -> ?GRPC_STATUS_RESOURCE_EXHAUSTED;
encode(failed_precondition) -> ?GRPC_STATUS_FAILED_PRECONDITION;
encode(aborted) -> ?GRPC_STATUS_ABORTED;
encode(out_of_range) -> ?GRPC_STATUS_OUT_OF_RANGE;
encode(unimplemented) -> ?GRPC_STATUS_UNIMPLEMENTED;
encode(internal) -> ?GRPC_STATUS_INTERNAL;
encode(unavailable) -> ?GRPC_STATUS_UNAVAILABLE;
encode(data_loss) -> ?GRPC_STATUS_DATA_LOSS;
encode(unauthenticated) -> ?GRPC_STATUS_UNAUTHENTICATED.

-spec decode(binary()) -> code().
decode(?GRPC_STATUS_OK) -> ok;
decode(?GRPC_STATUS_CANCELLED) -> cancelled;
decode(?GRPC_STATUS_UNKNOWN) -> unknown;
decode(?GRPC_STATUS_INVALID_ARGUMENT) -> invalid_argument;
decode(?GRPC_STATUS_DEADLINE_EXCEEDED) -> deadline_exceeded;
decode(?GRPC_STATUS_NOT_FOUND) -> not_found;
decode(?GRPC_STATUS_ALREADY_EXISTS ) -> already_exists;
decode(?GRPC_STATUS_PERMISSION_DENIED) -> permission_denied;
decode(?GRPC_STATUS_RESOURCE_EXHAUSTED) -> resource_exhausted;
decode(?GRPC_STATUS_FAILED_PRECONDITION) -> failed_precondition;
decode(?GRPC_STATUS_ABORTED) -> aborted;
decode(?GRPC_STATUS_OUT_OF_RANGE) -> out_of_range;
decode(?GRPC_STATUS_UNIMPLEMENTED) -> unimplemented;
decode(?GRPC_STATUS_INTERNAL) -> internal;
decode(?GRPC_STATUS_UNAVAILABLE) -> unavailable;
decode(?GRPC_STATUS_DATA_LOSS) -> data_loss;
decode(?GRPC_STATUS_UNAUTHENTICATED) -> unauthenticated.

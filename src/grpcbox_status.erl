-module(grpcbox_status).

-export([encode/1,
         decode/1,
         safe_decode/1]).

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
encode('OK') -> ?GRPC_STATUS_OK;
encode('CANCELLED') -> ?GRPC_STATUS_CANCELLED;
encode('UNKNOWN') -> ?GRPC_STATUS_UNKNOWN;
encode('INVALID_ARGUMENT') -> ?GRPC_STATUS_INVALID_ARGUMENT;
encode('DEADLINE_EXCEEDED') -> ?GRPC_STATUS_DEADLINE_EXCEEDED;
encode('NOT_FOUND') -> ?GRPC_STATUS_NOT_FOUND;
encode('ALREADY_EXISTS') -> ?GRPC_STATUS_ALREADY_EXISTS;
encode('PERMISSION_DENIED') -> ?GRPC_STATUS_PERMISSION_DENIED;
encode('RESOURCE_EXHAUSTED') -> ?GRPC_STATUS_RESOURCE_EXHAUSTED;
encode('FAILED_PRECONDITION') -> ?GRPC_STATUS_FAILED_PRECONDITION;
encode('ABORTED') -> ?GRPC_STATUS_ABORTED;
encode('OUT_OF_RANGE') -> ?GRPC_STATUS_OUT_OF_RANGE;
encode('UNIMPLEMENTED') -> ?GRPC_STATUS_UNIMPLEMENTED;
encode('INTERNAL') -> ?GRPC_STATUS_INTERNAL;
encode('UNAVAILABLE') -> ?GRPC_STATUS_UNAVAILABLE;
encode('DATA_LOSS') -> ?GRPC_STATUS_DATA_LOSS;
encode('UNAUTHENTICATED') -> ?GRPC_STATUS_UNAUTHENTICATED.

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

-spec safe_decode(binary()) -> {ok, code()} | error.
safe_decode(Code) ->
    try {ok, decode(Code)}
    catch
        error:function_clause ->
            error
    end.

%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.reflection.v1.ServerReflection.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-04-22T18:03:35+00:00 and should not be modified manually

-module(grpcbox_reflection_bhvr).

%% @doc 
-callback server_reflection_info(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().


%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.lb.v1.LoadBalancer.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-04-22T18:03:35+00:00 and should not be modified manually

-module(grpcbox_load_balancer_bhvr).

%% @doc 
-callback balance_load(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().


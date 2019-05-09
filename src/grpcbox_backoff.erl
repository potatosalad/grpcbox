%% See https://github.com/grpc/grpc/blob/master/doc/connection-backoff.md
-module(grpcbox_backoff).

-export([default/0,
	     new/5,
	     connecting/1,
	     ready/1,
	     transient_failure/1]).

-record(grpcbox_backoff, {
	current_backoff = timer:seconds(1) :: pos_integer(),
	current_deadline = timer:seconds(1) :: pos_integer(),
	%% INITIAL_BACKOFF (how long to wait after the first failure before retrying)
	initial_backoff = timer:seconds(1) :: pos_integer(),
	%% MULTIPLIER (factor with which to multiply backoff after a failed retry)
	multiplier = 1.6 :: float(),
	%% JITTER (by how much to randomize backoffs)
	jitter = 0.2 :: float(),
	%% MAX_BACKOFF (upper bound on backoff)
	max_backoff = timer:seconds(120),
	%% MIN_CONNECT_TIMEOUT (minimum time we're willing to give a connection to complete)
	min_connect_timeout = timer:seconds(20)
}).

-type t() :: #grpcbox_backoff{}.

-export_type([t/0]).

default() ->
	new(timer:seconds(1), 1.6, 0.2, timer:seconds(120), timer:seconds(20)).

new(InitialBackoff, Multiplier, Jitter, MaxBackoff, MinConnectTimeout)
		when (is_integer(InitialBackoff) andalso InitialBackoff > 0)
		andalso (is_float(Multiplier) andalso Multiplier > 0.0)
		andalso (is_float(Jitter) andalso Jitter > 0.0)
		andalso (is_integer(MaxBackoff) andalso MaxBackoff > 0 andalso MaxBackoff >= InitialBackoff)
		andalso (is_integer(MinConnectTimeout) andalso MinConnectTimeout > 0) ->
	#grpcbox_backoff{
		current_backoff = InitialBackoff,
		current_deadline = InitialBackoff,
		initial_backoff = InitialBackoff,
		multiplier = Multiplier,
		jitter = Jitter,
		max_backoff = MaxBackoff,
		min_connect_timeout = MinConnectTimeout
	}.

connecting(B=#grpcbox_backoff{current_deadline=CurrentDeadline, min_connect_timeout=MinConnectTimeout}) ->
	{max(CurrentDeadline, MinConnectTimeout), B}.

ready(B=#grpcbox_backoff{initial_backoff=InitialBackoff}) ->
	{InitialBackoff, B#grpcbox_backoff{current_backoff=InitialBackoff, current_deadline=InitialBackoff}}.

transient_failure(B=#grpcbox_backoff{current_backoff=CurrentBackoff, current_deadline=CurrentDeadline, multiplier=Multiplier, jitter=Jitter, max_backoff=MaxBackoff}) ->
	Backoff = min(round(CurrentBackoff * Multiplier), MaxBackoff),
	Deadline = Backoff + uniform_random(round(-Jitter * Backoff), round(Jitter * Backoff)),
	{CurrentDeadline, B#grpcbox_backoff{current_backoff=Backoff, current_deadline=Deadline}}.

%%

%% @private
uniform_random(0, High) when is_integer(High) andalso High >= 0 ->
	rand:uniform(High + 1) - 1;
uniform_random(Low, High) when is_integer(Low) andalso is_integer(High) andalso High >= 0 andalso (Low =< High) ->
	rand:uniform(High - Low + 1) + Low - 1.

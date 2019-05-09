-module(grpcbox_channel_sup).

-behaviour(supervisor).

-export([start_link/1]).
%% supervisor callbacks
-export([init/1]).

%% Top-level Channel
start_link(Name, Endpoints, Options) when is_list(Endpoints) andalso is_map(Options) ->
    supervisor:start_link(?MODULE, {top_level_channel, [Name, Endpoints, Options]}).

start_child(SupRef, Name, Target = #{'__struct__' := grpcbox_target}, Options) when is_pid(SupRef) ->


init({top_level_channel, [Name, Endpoints, Options]}) ->
    ChildSpecs = [#{id => grpcbox_channel,
                    start => {grpcbox_channel, start_link, [Name, Endpoints, Options]},
                    type => worker,
                    restart => permanent,
                    shutdown => 1000}
                 ],
    SupFlags = #{strategy => rest_for_one,
                 intensity => 5,
                 period => 10},
    {ok, {SupFlags, ChildSpecs}}.

%% @private
maybe_start_child(SupRef, ChildSpec = #{id := Id}) ->
    case supervisor:start_child(SupRef, ChildSpec) of
        {ok, Child} ->
            {ok, Child};
        {error, already_present} ->


    SupRef = sup_ref()
    ChildSpec = child_spec() | (List :: [term()])
    startchild_ret() = 
        {ok, Child :: child()} |
        {ok, Child :: child(), Info :: term()} |
        {error, startchild_err()}
    startchild_err() = 
        already_present | {already_started, Child :: child()} | term()

% start_link() ->
%     supervisor:start_link({local, ?SERVER}, ?MODULE, []).

% %% @doc Start a channel under the grpcbox channel supervisor.
% -spec start_child(atom(), [grpcbox_channel:endpoint()], grpcbox_channel:options()) -> {ok, pid()}.
% start_child(Name, Endpoints, Options) ->
%     supervisor:start_child(?SERVER, [Name, Endpoints, Options]).

% %% @doc Create a default child spec for starting a channel
% -spec channel_spec(atom(), [grpcbox_channel:endpoint()], grpcbox_channel:options())
%                   -> supervisor:child_spec().
% channel_spec(Name, Endpoints, Options) ->
%     #{id => grpcbox_channel,
%       start => {grpcbox_channel, start_link, [Name, Endpoints, Options]},
%       type => worker}.

% init(_Args) ->
%     ets:new(?CHANNELS_TAB, [named_table, set, public, {read_concurrency, true}]),

%     SupFlags = #{strategy => simple_one_for_one,
%                  intensity => 5,
%                  period => 10},
%     ChildSpecs = [#{id => grpcbox_channel,
%                     start => {grpcbox_channel, start_link, []},
%                     type => worker,
%                     restart => transient,
%                     shutdown => 1000}
%                  ],
%     {ok, {SupFlags, ChildSpecs}}.
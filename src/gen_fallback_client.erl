%%% @author Vladimir G. Sekissov <eryx67@gmail.com>
%%% @copyright (C) 2014, Vladimir G. Sekissov
%%% @doc Client with fallback connections
%%% ++++
%%% <p/>
%%% ++++
%%% Client tries to keep the _Primary_ connection or some _Secondary_ ones.
%%% When _Primary_ connection is established it shutdowns the secondary one.
%%% ++++
%%% <p/>
%%% ++++
%%% Connection specification `ServerSpec = {Module, Function, Arguments}`,
%%% ++++
%%% <p/>
%%% ++++
%%% Connection is created as
%%% [source,erlang]
%%% --------------------------------------------------
%%% apply(Module, Function, [ServerPid|Arguments]) -> {ok, Pid} | {error, Error}
%%% --------------------------------------------------
%%% On success connection must call
%%% [source,erlang]
%%% --------------------------------------------------
%%% gen_fallback_client:connection_connected(ServerPid)
%%% --------------------------------------------------
%%% and terminate on falure.
%%% ++++
%%% <p/>
%%% ++++
%%% If primary connection is established the secondary is terminated with
%%% `exit(Pid, shutdown)`.
%%% ++++
%%% <p/>
%%% ++++
%%% `handle_connected` and `handle_disconnected` callbacks are used for
%%% connection notification.
%%% ++++
%%% <p/>
%%% ++++
%%% The delay between connections attempts is regulated with
%%% [horizontal]
%%% check_interval::
%%% _{Min, Max}_, defaults `{5000, 500000}`,
%%% it is set to _Min_ after successful connection
%%% check_step::
%%% default 3, _check_interval_ is increased by this factor
%%% after unsuccessful connection attempt
%%% @end
%%% Created : 16 Jan 2014 by Vladimir G. Sekissov <eryx67@gmail.com>

-module(gen_fallback_client).

-behaviour(gen_server).

-export([start_link/5, start_link/6, stop/1, wait_connection/1]).

%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% internal exports
-export([connection_connected/1]).

-export_type([option/0]).

-callback init(term()) -> {ok, term()}.
-callback handle_call(term(), term(), term()) -> term().
-callback handle_cast(term(), term()) -> term().
-callback handle_info(term(), term()) -> term().
-callback terminate(term(), term()) -> none().
-callback code_change(term(), term(), term()) -> term().
-callback handle_connected(pid(), module(), term()) -> term().
-callback handle_disconnected(term()) -> term().

-include("../include/log.hrl").

-define(CHECK_INTERVAL_MIN, 5000). %% ms
-define(CHECK_INTERVAL_MAX, ?CHECK_INTERVAL_MIN * 100). %% ms
-define(CHECK_INTERVAL_STEP, 3).

-type msec() :: integer().
-type timestamp() :: {integer(), integer(), integer()}.
-type function_name() :: atom().
-type function_args() :: [term()].
-type mfa() :: {module(), function_name(), function_args()}.

-record(state, {
          current,
          primary,
          secondary,
          handler,
          handler_state,
          connected=false,
          check_tref,
          waiters = []
         }).

-record(server, {
          pid :: pid(),
          mfa :: mfa(),
          check_last :: timestamp(),
          check_timeout :: msec(),
          check_interval :: {msec(), msec()},
          check_step = ?CHECK_INTERVAL_STEP :: integer()
         }).

-type server_spec() :: mfa().

-type option() :: {check_interval, integer()} | {check_step, integer()}.

-spec start_link(Handler::module(), HandlerArgs::term(),
                 PrimarySrv::server_spec(), SecondarySrvs::[server_spec()],
                 Options::[option()]) ->
                        {ok, pid()} | term().
start_link(Handler, HandlerArgs, PrimarySrv, SecondarySrvs, Options) ->
    {ClientOpts, Options1} = extract_options(Options),
    InitArg = {Handler, HandlerArgs, PrimarySrv, SecondarySrvs, ClientOpts},
    gen_server:start_link(?MODULE, InitArg, Options1).

-spec start_link(ServerName::term(), Handler::module(), HandlerArgs::term(),
                 PrimarySrv::server_spec(), SecondarySrvs::[server_spec()],
                 Options::[option()]) ->
                        {ok, pid()} | term().
start_link(ServerName, Handler, HandlerArgs, PrimarySrv, SecondarySrvs, Options) ->
    {ClientOpts, Options1} = extract_options(Options),
    InitArg = {Handler, HandlerArgs, PrimarySrv, SecondarySrvs, ClientOpts},
    gen_server:start_link(ServerName, ?MODULE, InitArg, Options1).

-spec wait_connection(pid()) ->
                             ok | {error, not_connected} | no_return().
wait_connection(Srv) ->
    wait_connection(Srv, 5000).

-spec wait_connection(pid(), integer() | infinity) ->
                             ok | {error, not_connected} | no_return().
wait_connection(Srv, Timeout) ->
    try gen_server:call(Srv, {wait_connection, self()}, Timeout)
    catch
        exit:{timeout,_} ->
            gen_server:cast(Srv, {unwait_connection, self()}),
            {error, not_connected}
    end.

extract_options(Opts) ->
    Keys = [check_interval, check_step],
    {Vals, Opts1} = emb_util:proplist_extract(Keys, validate_client_options(Opts)),
    {lists:zip(Keys, Vals), Opts1}.

stop(Srv) ->
    gen_server:cast(Srv, {stop}).

%% internal export for connection driver
connection_connected(Srv) ->
    gen_server:cast(Srv, {connected, self()}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init({Handler, HandlerArgs, PrimarySrv, SecondarySrvs, Opts}) ->
    Primary = validate_server_spec(PrimarySrv, Opts),
    Secondary = [validate_server_spec(S, Opts) || S <- SecondarySrvs],
    {ok, HandlerState} = Handler:init(HandlerArgs),
    process_flag(trap_exit, true),
    State = #state{
               primary=Primary,
               secondary=Secondary,
               handler=Handler,
               handler_state=HandlerState
              },
    {ok, State, 0}.

handle_call({wait_connection, _}, _From, S=#state{connected=true}) ->
    {reply, ok, S};
handle_call({wait_connection, Pid}, From, S=#state{connected=false, waiters=Ws}) ->
    {noreply, S#state{waiters=[{Pid, From}|Ws]}};
handle_call(_Msg, _From, S=#state{connected=false}) ->
    {reply, {error, not_connected}, S};
handle_call(Msg, From, S=#state{handler=Hlr, handler_state=HlrS}) ->
    wrap(Hlr:handle_call(Msg, From, HlrS), S).

handle_cast({unwait_connection, Pid}, S=#state{waiters=Ws}) ->
    {noreply, S#state{waiters=lists:keydelete(Pid, 1, Ws)}};
handle_cast({stop}, State) ->
    {stop, normal, State};
handle_cast({connected, ConPid}, State) ->
    S1 = do_handle_connected(ConPid, State),
    {noreply, S1};
handle_cast(Msg, S=#state{handler=Hlr, handler_state=HlrS}) ->
    wrap(Hlr:handle_cast(Msg, HlrS), S).

handle_info(timeout, State) ->
    {noreply, start_check_fallback(State)};
handle_info({check_fallback}, State) ->
    {noreply, start_check_fallback(State)};
handle_info({'EXIT', Pid, Reason}, S=#state{current=#server{pid=Pid}}) ->
    ?error("current connection failed ~p, ~p", [Pid, Reason]),
    {noreply, do_handle_server_exited(Pid, S)};
handle_info({'EXIT', Pid, Reason}, S=#state{primary=#server{pid=Pid}}) ->
    ?error("connection to primary server failed ~p, ~p", [Pid, Reason]),
    {noreply, do_handle_server_exited(Pid, S)};
handle_info(Msg, S=#state{handler=Hlr, handler_state=HlrS}) ->
    wrap(Hlr:handle_info(Msg, HlrS), S).

terminate(Reason, S=#state{current=Current, primary=Primary,
                           handler=Hlr, handler_state=HlrS}) ->
    stop_check_fallback(S),
    case Current of
        undefined ->
            ok;
        _ ->
            server_disconnect(Current)
    end,
    server_disconnect(Primary),
    Hlr:terminate(Reason, HlrS),
    ok.

code_change(OldVsn, State=#state{handler=Hlr, handler_state=HlrS}, Extra) ->
    {ok, HlrS1} = Hlr:code_change(OldVsn, HlrS, Extra),
    {ok, State#state{handler_state=HlrS1}}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
do_handle_connected(ConPid, S=#state{current=#server{pid=ConPid}}) ->
    do_handle_connected_current(ConPid, S);
do_handle_connected(ConPid, S=#state{primary=#server{pid=ConPid}}) ->
    do_handle_connected_primary(ConPid, S).

do_handle_connected_current(Pid, S=#state{current=Current,
                                          handler=Hlr, handler_state=HlrS,
                                          waiters=Ws}) ->
    S1 = stop_check_fallback(S),
    Current1 = server_connected(Current),
    #server{mfa={M, _, _}} = Current1,
    {ok, HlrS1} = Hlr:handle_connected(Pid, M, HlrS),
    [gen_server:reply(From, ok) || {_, From} <- Ws],
    S2 = S1#state{current=Current1,
                  handler_state=HlrS1,
                  connected=true,
                  waiters=[]},
    S3 = start_check_fallback(S2),
    S3.

do_handle_connected_primary(Pid, S=#state{current=Current, primary=Primary}) ->
    server_disconnect(Current),
    S1 = current_disconnected(S),
    S2 = S1#state{current=Primary},
    do_handle_connected_current(Pid, S2).

do_handle_server_exited(Pid, S=#state{current=#server{pid=Pid}}) ->
    S1 = current_disconnected(S),
    S2 = start_check_fallback(S1),
    S2;
do_handle_server_exited(Pid, S=#state{primary=Primary=#server{pid=Pid}}) ->
    Primary1 = server_exited(Primary),
    S2 = S#state{primary=Primary1},
    S3 = start_check_fallback(S2),
    S3.

current_disconnected(S=#state{current=Current,
                              handler=Hlr, handler_state=HlrS}) ->
    Current1 = server_exited(Current),
    S1 = set_server_state(Current, Current1, S),
    {ok, HlrS1} = Hlr:handle_disconnected(HlrS),
    S2 = S1#state{current=undefined, handler_state=HlrS1, connected=false},
    S2.

server_exited(Srv=#server{check_step=CS, check_timeout=CT, check_interval={CMin, CMax}}) ->
    CT1 = incr_check_interval(CT, CS, CMin, CMax),
    Srv#server{pid=undefined, check_timeout=CT1, check_last=erlang:now()}.

server_connected(Srv=#server{check_interval={CMin, _}}) ->
    Srv#server{check_timeout=CMin, check_last=undefined}.

server_disconnect(Srv=#server{pid=Pid}) when is_pid(Pid) ->
    unlink(Pid),
    exit(Pid, shutdown),
    Srv#server{pid=undefined};
server_disconnect(Srv) ->
    Srv.

set_server_state(_Srv=#server{pid=Pid}, NewSrv, S=#state{primary=#server{pid=Pid}}) ->
    S#state{primary=NewSrv};
set_server_state(Srv=#server{pid=Pid}, NewSrv, S=#state{secondary=Secondary}) ->
    S#state{secondary=[if SS#server.pid == Pid -> Srv;
                          true -> NewSrv
                       end || SS <- Secondary]}.

start_connection(Srv=#server{mfa={M, F, A}}) ->
    {ok, Pid} = apply(M, F, [self()|A]),
    ?debug("trying to connect ~p, ~p", [{M, F, A}, Pid]),
    Srv#server{pid=Pid}.

start_check_fallback(S=#state{current=undefined, primary=Primary, secondary=Secondary}) ->
    case lists:keysort(2, [{Srv, server_check_delay(Srv)} || Srv <- [Primary|Secondary]]) of
        [{Primary, 0}|_] ->
            Current = start_connection(Primary),
            S#state{current=Current, primary=Current};
        [{CheckSrv, 0}|_] ->
            S#state{current=start_connection(CheckSrv)};
        [{_, Delay}|_] ->
            start_check_timer(Delay + 1000, S)
    end;
start_check_fallback(S=#state{current=#server{pid=Pid}, primary=#server{pid=Pid}}) ->
    S;
start_check_fallback(S=#state{primary=Primary}) ->
    Delay = server_check_delay(Primary),
    case Delay of
        0 ->
            start_connection(Primary),
            S#state{primary=Primary};
        _ ->
            start_check_timer(Delay + 1000, S)
    end.

stop_check_fallback(State) ->
    clear_check_timer(State).

server_check_delay(#server{check_last = undefined}) ->
    0;
server_check_delay(#server{check_last = LastTime,
                           check_timeout = CT}) ->
    Now = erlang:now(),
    Diff = timer:now_diff(Now, LastTime) div 1000,
    erlang:trunc(max(0, CT - Diff)).

start_check_timer(Delay, S) ->
    TRef = erlang:send_after(Delay, self(), {check_fallback}),
    S#state{check_tref=TRef}.

clear_check_timer(S=#state{check_tref=undefined}) ->
    S;
clear_check_timer(S=#state{check_tref=ST}) ->
    erlang:cancel_timer(ST),
    S#state{check_tref=undefined}.

incr_check_interval(undefined, _CS, CMin, _CMax) ->
    CMin;
incr_check_interval(Timeout, Step, _CMin, CMax) ->
    erlang:trunc(min(Timeout * Step, CMax)).

wrap({reply, Reply, NewState}, State) ->
    {reply, Reply, State#state{handler_state = NewState}};
wrap({reply, Reply, NewState, Timeout}, State) ->
    {reply, Reply, State#state{handler_state = NewState}, Timeout};
wrap({noreply, NewState}, State) ->
    {noreply, State#state{handler_state = NewState}};
wrap({noreply, NewState, Timeout}, State) ->
    {noreply, State#state{handler_state = NewState}, Timeout};
wrap({stop, Reason, Reply, NewState}, State) ->
    {stop, Reason, Reply, State#state{handler_state = NewState}};
wrap({stop, Reason, NewState}, State) ->
    {stop, Reason, State#state{handler_state = NewState}}.

validate_client_options(Opts) ->
    emb_util:proplist_validate(Opts,
                               [],
                               [{check_interval, fun validate_check_interval/1}
                               , {check_step, fun validate_check_step/1}
                               ],
                               [{check_interval, {?CHECK_INTERVAL_MIN, ?CHECK_INTERVAL_MAX}}
                               , {check_step, ?CHECK_INTERVAL_STEP}
                               ]).

validate_server_spec(MFA={_M, _F, _A}, Opts) ->
    [CheckInterval, CheckStep] = emb_util:proplist_require([check_interval, check_step],
                                                           Opts),
    {CMin, _} = CheckInterval,
    #server{
       mfa=MFA,
       check_step=CheckStep,
       check_timeout = CMin,
       check_interval = CheckInterval
      }.

validate_check_interval(CheckInterval) when is_integer(CheckInterval) ->
    Mul = ?CHECK_INTERVAL_MAX / ?CHECK_INTERVAL_MIN,
    CheckIntervalMax = erlang:trunc(CheckInterval * Mul),
    {CheckInterval, CheckIntervalMax};
validate_check_interval(V={Min, Max}) when is_integer(Min)
                                           andalso is_integer(Max)
                                           andalso Min =< Max ->
    V.

validate_check_step(V) when is_integer(V),
                            V > 0 ->
    V.

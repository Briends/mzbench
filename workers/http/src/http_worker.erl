-module(http_worker).

-export([initial_state/0, metrics/0]).

-export([set_host/3, set_port/3,
    get/3,
    post/4, post/5]).

-type meta() :: [{Key :: atom(), Value :: any()}].
-type headers() :: [{Key :: string(), Value :: string()}].
-type http_host() :: string().
-type http_port() :: integer().

-record(state,
    { host :: http_host()
    , port :: http_port()
    }).

-type state() :: #state{}.

-define(TIMED(Name, Expr),
    (fun () ->
        StartTime = os:timestamp(),
        Result = Expr,
        Value = timer:now_diff(os:timestamp(), StartTime),
        mzb_metrics:notify({Name, histogram}, Value),
        Result
    end)()).

-spec initial_state() -> state().
initial_state() ->
    #state{}.

-spec metrics() -> list().
metrics() ->
    [ [{"http_ok", counter}, {"http_fail", counter}, {"other_fail", counter}]
    , {"latency", histogram}
    ].

-spec set_host(state(), meta(), string()) -> {nil, state()}.
set_host(State, _Meta, NewHost) ->
    {nil, State#state{host = NewHost}}.

-spec set_port(state(), meta(), http_port()) -> {nil, state()}.
set_port(State, _Meta, NewPort) ->
    {nil, State#state{port = NewPort}}.

-spec get(state(), meta(), string()) -> {nil, state()}.
get(#state{host = Host, port = Port} = State, _Meta, Endpoint) ->
    URL = lists:flatten(io_lib:format("http://~s:~p~s", [Host, Port, Endpoint])),
    Response = ?TIMED("latency", hackney:request(
        get, list_to_binary(URL), [], <<"">>, [])),
    record_response(Response),
    {nil, State}.

-spec post(state(), meta(), string(), iodata()) -> {nil, state()}.
post(State, Meta, Endpoint, Payload) ->
    post(State, Meta, [], Endpoint, Payload).

-spec post(state(), meta(), headers(), string(), iodata()) -> {nil, state()}.
post(#state{host = Host, port = Port} = State, _Meta, Headers, Endpoint, Payload) ->
    URL = lists:flatten(io_lib:format("~s:~p~s", [Host, Port, Endpoint])),
    Response = ?TIMED("latency", hackney:request(
        post, list_to_binary(URL), Headers, Payload, [{follow_redirect, true}, {recv_timeout, infinity}])),
    record_response(Response),
    {nil, State}.

record_response(Response) ->
    case Response of
        {ok, Code, _, BodyRef} when Code >= 200, Code < 300 ->
            hackney:body(BodyRef),
            mzb_metrics:notify({"http_ok", counter}, 1);
        {ok, Code, _, BodyRef} ->
            {ok, Body}  = hackney:body(BodyRef),
            lager:warning("hackney:request status: ~p: ~s", [Code, Body]),
            mzb_metrics:notify({"http_fail", counter}, 1);
        E ->
            lager:error("hackney:request failed: ~p", [E]),
            mzb_metrics:notify({"other_fail", counter}, 1)
    end.

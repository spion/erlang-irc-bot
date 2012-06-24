-module(plugins.prisutni).
-author("gorgi.kosev@gmail.com").

-behaviour(gen_event).
-export([init/1, handle_event/2, terminate/2, handle_call/2, handle_info/2, code_change/3]).


-import(ircbot_lib).

-import(ejson).
-import(lists).
-import(proplists).
-import(http).
-import(inets).
-import(ssl).
-import(string).

init(_Args) ->
    inets:start(),
    {ok, ok}.


handle_event(Msg, State) ->
    case Msg of
        % explicit command to fetch prisutni.spodeli.org
        {in, Ref, [_Nick, _Name, <<"PRIVMSG">>, <<"#",Channel/binary>>, <<"!prisutni">>]} ->
            fetch("http://prisutni.spodeli.org/status?limit=1", Ref, <<"#",Channel/binary>>),
            {ok, State};
       _ ->
            {ok, State}
    end.
handle_call(_Request, State) -> {ok, ok, State}.
handle_info(_Info, State) -> {ok, State}.
code_change(_OldVsn, State, _Extra) -> {ok, State}.
terminate(_Args, _State) -> ok.



% Fetch the json, but not more than 10kbytes
%% The function gets spawned as a separate process, and fails silently on any
%% error.
fetch(Url, Ref, Channel) ->
    F = fun(Answer) -> Ref:privmsg(Channel, Answer) end,
    spawn(fun() -> fetcher(Url, F) end).

fetcher(Url, Callback) ->
    Headers = [{"User-Agent", "Mozilla/5.0 (erlang-irc-bot)"}],
    io:format("Sending request ~n"),
    {ok, RequestId} = http:request(get, {Url, Headers}, [], [{sync, false}, {stream, self}]),
    io:format("receive_chunk 01 ~n"),
    receive_chunk(RequestId, Callback, [], 1).

%% callback function called as chunks from http are received
%% when enough data is received (Len =< 0) process the json

receive_chunk(_RequestId, Callback, Body, Len) when Len =< 0 ->
    %io:format("receive_chunk end ~n"),
    {Json} = ejson:decode(Body),
    Count = proplists:get_value(<<"count">>, element(1, lists:last(proplists:get_value(<<"counters">>, Json)))),
    People = lists:map(fun(P) -> binary_to_list(proplists:get_value(<<"name">>, element(1, P))) end, proplists:get_value(<<"present">>, Json)),
    Answer = lists:concat([string:join(People, " ")," (",Count," devices total",")"]),                
    
    Callback(Answer);

receive_chunk(RequestId, Callback, Body, Len)  ->
    receive
        {http,{RequestId, stream_start, Headers}} ->
            io:format("receive_chunk 02 ~n"),
            receive_chunk(RequestId, Callback, Body, 1);

        {http,{RequestId, stream, Data}} ->
            io:format("receive_chunk 03 ~n"),
            receive_chunk(RequestId, Callback, Body ++ [Data], 1);

        {http,{RequestId, stream_end, Headers}} ->
            io:format("receive_chunk 04 ~n"),
            receive_chunk(RequestId, Callback, Body, 0)
    end.


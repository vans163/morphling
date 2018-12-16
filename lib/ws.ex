defmodule Morphling.HTTP do
    def http(:'GET', "/morphling.js", _, h, _, s) do
        :stargate_plugin.serve_static("./priv/", "morphling.js", h, s)
    end
    def http(:'GET', "/", _, h, _, s) do
        IO.inspect "/"

        {pid, dom} = init_morphling()
        cookie_key = :crypto.strong_rand_bytes(64) |> Base.encode64(ignore: :whitespace, padding: false)
        :yes = :global.register_name(cookie_key, pid)
        h_new = %{"Set-Cookie"=> "morphling_ticket=#{cookie_key}"}

        {code, headersReply, binReply, s} = :stargate_plugin.serve_static_bin(dom, h, s)
        {code, Map.merge(headersReply, h_new), binReply, s}
    end

    def init_morphling(_cookie\\"") do
        morphling_state = %{table_names: [{"Jill","Smith","50"},{"Mike","Jones","150"}]}
        pid = Morphling.Ex.create(&Morphling.HTTP.page/1, morphling_state, 120000)
        {dom,_} = Morphling.Ex.diff_dom(pid, "")
        {pid, dom}
    end

    def page(s\\%{}) do
        """
        <!DOCTYPE html>
        <html>
            <head>
                <link rel="icon" type="image/png" href="data:image/png;base64,iVBORw0KGgo=">
                <script src="https://npmcdn.com/morphdom@2.3.3/dist/morphdom-umd.js"></script>
                <script src="/morphling.js"></script>
            </head>
            <body>
                <h1>My First Morphling</h1>
                <input value=#{s["aa"]}></input>
                #{page_table(s)}
                <p onclick=m("click_para")>My firstt paragraph.</p>
            </body>
            <script>
                Morphling("ws://localhost:8090/ws");
            </script>
        </html>
        """
    end

    def page_table(s) do
        names = Map.get(s,:table_names,[])
        """
        <table>
          <tr>
            <th>Firstname</th>
            <th>Lastname</th> 
            <th>Age</th>
          </tr>
          #{Enum.reduce(names,"",fn({a,b,c},acc)-> acc<>"<tr><td>#{a}</td><td>#{b}</td><td>#{c}</td></tr>" end)}
        </table>
        """
    end
end

defmodule Morphling.WS do
    use GenServer

    def start_link(params), do: :gen_server.start_link(__MODULE__, params, [])

    def init({parent_pid, _query, headers, state}) do
        IO.inspect "connect"

        pid = :global.whereis_name(:stargate_plugin.cookie_parse(headers["cookie"])["morphling_ticket"])
        cond do
            pid == :undefined ->
                IO.inspect "recreate morphling session"
                {pid, dom} = Morphling.HTTP.init_morphling()
                send(parent_pid, {:ws_send, {:text_compress, Morphling.Ex.encode_dom_diff(dom)}})
                state = Map.merge(state, %{parent_pid: parent_pid, morphling_dom: dom, morphling_pid: pid})
                {:ok, state}

            true ->
                IO.inspect "found morphling session"
                {dom,_} = Morphling.Ex.diff_dom(pid, "")
                send(parent_pid, {:ws_send, {:text_compress, Morphling.Ex.encode_dom_diff(dom)}})
                state = Map.merge(state, %{parent_pid: parent_pid, morphling_dom: dom, morphling_pid: pid})
                {:ok, state}
        end
    end

    def handle_info({:text, bin}, s) do
        IO.inspect bin
        map = JSX.decode!(bin)

        morphling_state = Morphling.Ex.state(s.morphling_pid)
        table_names = morphling_state[:table_names]
        table_names = table_names ++ [{"morph!", "ahhhh", "spla21"}]
        morphling_state = %{morphling_state|table_names: table_names}
        Morphling.Ex.merge_nested(s.morphling_pid, morphling_state)

        {dom,_} = Morphling.Ex.diff_dom(s.morphling_pid, "")

        send(s.parent_pid, {:ws_send, {:text_compress, Morphling.Ex.encode_dom_diff(dom)}})

        #send(s.parent_pid, {:ws_send, {:text_compress, "hello"}})
        #ParentPid ! {ws_send, {bin_compress, <<"hello compressed">>}},
        #ParentPid ! {ws_send, {text_compress, <<"a websocket text msg compressed">>}},
        {:noreply, s}
    end
end

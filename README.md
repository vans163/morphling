# Morphling
Elixir library for server driven DOM morphing. Never write Javascript again!

<img src="https://cdnb.artstation.com/p/assets/images/images/000/442/403/large/hai-dang-untitled-541-001.jpg" width="960" height="600" />

### Description
Morphling uses server side HTML DOM rendering (think PHP), except it sends differential of
the created HTML DOM to the frontend and 'morphs' it ontop of the current DOM.  
  
This results in React like realtime responsiveness without having to operate inside the Javascript VM,  
interop with the Javascript Ecosystem nor communicate with the Javascript community.
  
### Why Morphling and not LiveView or Drab?
Morphling is not tied to Pheonix and lets you implement your own business logic.  Morphling gives you the morphling.js file
which the client browser must load to setup the websock connection, and it gives you the Morphling, which deals with creating 
DOM differentials and managing the server side state.

### Example Usage with Stargate Webserver
```elixir
defmodule Demo.Mixfile do
    use Mix.Project

    def project, do: [
        app: :demo,
        version: "0.0.1",
        elixir: "~> 1.6",
        build_embedded: Mix.env == :prod,
        start_permanent: Mix.env == :prod,
        deps: deps(),
    ]

    def application, do: [
        applications: [:logger],
    ]

    def deps, do: [
        {:exjsx, "~> 4.0.0"},
        {:stargate, git: "https://github.com/vans163/stargate.git"},
        {:morphling, git: "https://github.com/vans163/morphling.git"},
    ]
end

defmodule Demo do
    use Application

    def start(_type, _args) do
        import Supervisor.Spec, warn: false

        IO.puts "Starting webserver.."
        {:ok, _} = :application.ensure_all_started(:stargate)
        webserver = %{
            ip: {0,0,0,0},
            port: 8090,
            hosts: %{
                {:http, "*"}=> {Demo.HTTP, %{}},
                {:ws, "*"}=> {Demo.WS, %{}}
            }
        }
        {:ok, _Pid} = :stargate.warp_in(webserver)

        children = [
        ]
        opts = [strategy: :one_for_one,
            name: Demo.Supervisor,
            max_seconds: 1,
            max_restarts: 999999999999]
        Supervisor.start_link(children, opts)
    end
end

defmodule Demo.HTTP do
    def http(:'GET', "/morphling.js", _, h, _, s) do
        path = "#{:code.priv_dir(:morphling)}/morphling.js"
        bin = File.read!(path)
        :stargate_plugin.serve_static_bin(bin, h, s)
    end
    def http(:'GET', path, _, h, _, s) do
        IO.inspect path

        ms = %{path: path}
        {dom, _} = Demo.WS.refresh_page("", ms)
        :stargate_plugin.serve_static_bin(dom, h, s)
    end
end

defmodule Morphling.WS do
    use GenServer

    def start_link(params), do: :gen_server.start_link(__MODULE__, params, [])

    def init({parent_pid, _query, headers, state}) do
        IO.inspect "connect"

        path = query["path"]

        ms = %{path: path}
        {dom, ms} = Demo.WS.refresh_page("", ms, parent_pid)

        state = Map.merge(state, %{parent_pid: parent_pid, morph_dom: dom, morph_state: ms})
        {:ok, state}
    end

    def refresh_page(old_dom, ms, parent_pid \\ nil) do
        path = ms[:path]
        ms_new = cond do
            path != nil ->
                default_value = Map.get(ms, :value, 0)
                Map.merge(ms, %{value: default_value})
            true -> ms
        end

        new_dom = Demo.Page.render(ms_new)

        if parent_pid != nil do
            diff = Morphling.diff_dom(old_dom, new_dom)
            send(parent_pid, {:ws_send, {:text_compress, Morphling.encode_dom_diff(diff)}})
            send(parent_pid, {:ws_send, {:text_compress, Morphling.encode_rpc_navigate(ms_new[:path])}})
        end
        {new_dom, ms_new}
    end

    def handle_info({:text, bin}, s) do
        IO.inspect bin
        map = JSX.decode!(bin)

        ms = s.morph_state
        ms = cond do
            map["action"] == "click_button" ->
                Map.merge(ms, %{value: map["args"]+1})
        end

        {dom, ms} = Demo.WS.refresh_page(s.morph_dom, ms, s.parent_pid)
        {:noreply, %{s|morph_dom: dom, morph_state: ms}}
    end
end

defmodule Demo.Page do
    def render(s\\%{}) do
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
                <input value=#{s[:value]}></input>
                #{page_table(s)}
                <p onclick=m("click_button", s[:value])>My firstt paragraph.</p>
            </body>
            <script>
                Morphling(`ws://localhost:8090/?path=${location.pathname}`);
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
```

Now edit the text and recompile the app, click button again, watch the dom auto hotload and mount without needing to refresh the page.
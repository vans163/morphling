defmodule Morphling do
    use Application

    def start(_type, _args) do
        import Supervisor.Spec, warn: false

        IO.puts "Starting webserver.."
        {:ok, _} = :application.ensure_all_started(:stargate)
        webserver = %{
            ip: {0,0,0,0},
            port: 8090,
            hosts: %{
                {:http, "*"}=> {Morphling.HTTP, %{}},
                {:ws, "*"}=> {Morphling.WS, %{}}
            }
        }
        {:ok, _Pid} = :stargate.warp_in(webserver)

        children = [
        ]
        opts = [strategy: :one_for_one,
            name: Morphling.Supervisor,
            max_seconds: 1,
            max_restarts: 999999999999]
        Supervisor.start_link(children, opts)
    end
end

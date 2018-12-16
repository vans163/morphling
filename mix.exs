defmodule Morphling.Mixfile do
    use Mix.Project

    def project, do: [
        app: :morphling,
        version: "0.0.1",
        elixir: "~> 1.6",
        build_embedded: Mix.env == :prod,
        start_permanent: Mix.env == :prod,
        deps: deps(),
    ]

    def application, do: [
        applications: [:logger],
        mod: {Morphling, []}
    ]

    def deps, do: [
        {:exjsx, "~> 4.0.0"},
        {:stargate, git: "https://github.com/vans163/stargate.git"},
    ]
end

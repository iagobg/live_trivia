defmodule LiveTrivia.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LiveTriviaWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:live_trivia, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LiveTrivia.PubSub},
      LiveTriviaWeb.Presence,
      {Registry, keys: :unique, name: LiveTrivia.GameRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: LiveTrivia.RoomSupervisor},
      LiveTrivia.Lobby,
      # Start to serve requests, typically the last entry
      LiveTriviaWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LiveTrivia.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LiveTriviaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

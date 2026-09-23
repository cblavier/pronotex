defmodule Pronotex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Pronotex.Repo,
      {Ecto.Migrator, repos: [Pronotex.Repo]},
      PronotexWeb.Telemetry,
      Pronotex.Auth,
      Pronotex.Pronote.ReadCache,
      Pronotex.Pronote.Session,
      {Registry, keys: :unique, name: Pronotex.Pronote.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Pronotex.Pronote.Supervisor},
      {DNSCluster, query: Application.get_env(:pronotex, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pronotex.PubSub},
      {Task.Supervisor, name: Pronotex.RefreshTasks},
      Pronotex.Push.Worker,
      Pronotex.Pronote.BackgroundRefresh,
      # Start a worker by calling: Pronotex.Worker.start_link(arg)
      # {Pronotex.Worker, arg},
      # Start to serve requests, typically the last entry
      PronotexWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pronotex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PronotexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

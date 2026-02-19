defmodule ElegooElixir.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if headless_cli?() do
        [
          {Phoenix.PubSub, name: ElegooElixir.PubSub},
          ElegooElixir.CarTcpClient
        ]
      else
        [
          ElegooElixirWeb.Telemetry,
          ElegooElixir.Repo,
          {Ecto.Migrator,
           repos: Application.fetch_env!(:elegoo_elixir, :ecto_repos), skip: skip_migrations?()},
          {DNSCluster, query: Application.get_env(:elegoo_elixir, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: ElegooElixir.PubSub},
          ElegooElixir.CarTcpClient,
          # Start a worker by calling: ElegooElixir.Worker.start_link(arg)
          # {ElegooElixir.Worker, arg},
          # Start to serve requests, typically the last entry
          ElegooElixirWeb.Endpoint
        ]
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ElegooElixir.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ElegooElixirWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end

  defp headless_cli? do
    Application.get_env(:elegoo_elixir, :headless_cli, false)
  end
end

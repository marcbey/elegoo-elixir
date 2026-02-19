defmodule ElegooElixir.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = app_children(headless_cli?())
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

  defp headless_cli? do
    Application.get_env(:elegoo_elixir, :headless_cli, false)
  end

  defp app_children(true) do
    [
      {Phoenix.PubSub, name: ElegooElixir.PubSub},
      ElegooElixir.CarTcpClient
    ]
  end

  defp app_children(false) do
    [
      ElegooElixirWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:elegoo_elixir, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ElegooElixir.PubSub},
      ElegooElixir.CarTcpClient,
      ElegooElixirWeb.Endpoint
    ]
  end
end

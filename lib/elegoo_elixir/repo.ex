defmodule ElegooElixir.Repo do
  use Ecto.Repo,
    otp_app: :elegoo_elixir,
    adapter: Ecto.Adapters.SQLite3
end

# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :elegoo_elixir, :car,
  host: "192.168.4.1",
  port: 100,
  stream_url: "http://192.168.4.1:81/stream",
  reconnect_ms: 1_000,
  control_tick_ms: 40,
  sensor_poll_ms: 250,
  cli_timeout_ms: 1_500

config :elegoo_elixir, :speech,
  provider: "whisper_local",
  base_url: "http://127.0.0.1:8088",
  path: "/inference",
  stt_timeout_ms: 10_000,
  stt_language: "en",
  whisper_autostart: false,
  whisper_launch_cmd: nil,
  whisper_restart_ms: 5_000,
  voice_max_clip_ms: 4_500,
  voice_min_command_interval_ms: 250,
  voice_default_speed: 120

# Configure the endpoint
config :elegoo_elixir, ElegooElixirWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ElegooElixirWeb.ErrorHTML, json: ElegooElixirWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ElegooElixir.PubSub,
  live_view: [signing_salt: "WP3ppz7U"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  elegoo_elixir: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  elegoo_elixir: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

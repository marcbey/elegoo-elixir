defmodule ElegooElixirWeb.Router do
  use ElegooElixirWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ElegooElixirWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ElegooElixirWeb do
    pipe_through :browser

    live "/", ControlLive
  end

  scope "/api", ElegooElixirWeb do
    pipe_through :api

    post "/speech/transcribe", SpeechController, :transcribe
  end
end

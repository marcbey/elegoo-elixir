defmodule ElegooElixirWeb.PageController do
  use ElegooElixirWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

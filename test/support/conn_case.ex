defmodule ElegooElixirWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by tests
  that require setting up an HTTP connection.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint ElegooElixirWeb.Endpoint

      use ElegooElixirWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import ElegooElixirWeb.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end

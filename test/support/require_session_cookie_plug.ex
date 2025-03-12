defmodule PhoenixTest.Plugs.RequireSessionCookiePlug do
  @moduledoc """
  Allows conn to pass if it has the correct cookie.

  If no cookie, or invalid cookie, returns 403.
  """
  import Plug.Conn

  def init(_opts), do: nil

  def call(conn, _opts) do
    conn
    |> fetch_session()
    |> ensure_correct()
  end

  defp ensure_correct(conn) do
    if get_session(conn, :secret) == "mighty_boosh" do
      conn
    else
      conn
      |> put_status(403)
      |> halt()
    end
  end
end

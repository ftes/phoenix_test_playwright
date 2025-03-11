defmodule PhoenixTest.Plugs.RequireCookiePlug do
  @moduledoc """
  Allows conn to pass if it has the correct cookie.

  If no cookie, or invalid cookie, returns 403.
  """
  import Phoenix.Controller, only: [protect_from_forgery: 1]
  import Plug.Conn

  @encrypted_cookie "encrypted_cookie"
  @signed_cookie "signed_cookie"
  @plain_cookie "plain_cookie"

  def cookie_name(:encrypted), do: @encrypted_cookie
  def cookie_name(:signed), do: @signed_cookie
  def cookie_name(:plain), do: @plain_cookie

  def cookie_options(:encrypted) do
    [sign: false, encrypt: true, same_site: "Strict", http_only: true, secure: true]
  end

  def cookie_options(:signed) do
    [sign: true, encrypt: false, same_site: "Lax", http_only: false, secure: false]
  end

  def cookie_options(:plain) do
    [sign: false, encrypt: false, same_site: "Lax", http_only: false, secure: false]
  end

  def init(_opts), do: nil

  def call(conn, _opts) do
    conn
    |> fetch_cookies(signed: [@signed_cookie], encrypted: [@encrypted_cookie])
    |> protect_from_forgery()
    |> ensure_correct()
  end

  defp ensure_correct(conn) do
    case Map.get(conn.cookies, @encrypted_cookie) || Map.get(conn.cookies, @signed_cookie) ||
           Map.get(conn.cookies, @plain_cookie) do
      %{secret: "mighty_boosh"} ->
        conn

      "the secret is mighty_boosh" ->
        conn

      _ ->
        conn
        |> put_status(403)
        |> halt()
    end
  end
end

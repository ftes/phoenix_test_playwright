defmodule PhoenixTest.Playwright.PageController do
  use Phoenix.Controller, formats: [html: "View"]

  def blank(conn, _), do: send_resp(conn, 200, "")

  def download(conn, _) do
    send_download(conn, {:file, "test/files/elixir.jpg"})
  end

  def js_script_console_error(conn, _) do
    render(conn, "js_script_console_error.html")
  end

  def cookies(conn, params) do
    conn
    |> assign(:id, "cookies")
    |> fetch_cookies(encrypted: params["encrypted"] || [], signed: params["signed"] || [])
    |> then(&assign(&1, :data, &1.cookies))
    |> render("data.html")
  end

  def session(conn, _) do
    conn
    |> assign(:id, "session")
    |> assign(:data, get_session(conn))
    |> render("data.html")
  end

  def headers(conn, _) do
    conn
    |> assign(:id, "headers")
    |> assign(:data, conn.req_headers)
    |> render("data.html")
  end
end

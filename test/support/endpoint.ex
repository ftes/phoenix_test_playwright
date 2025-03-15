defmodule PhoenixTest.Endpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :phoenix_test_playwright

  @session_options [
    store: :cookie,
    key: "_phoenix_test_key",
    signing_salt: "/VADsdfSfdMnp5"
  ]

  socket("/live", Phoenix.LiveView.Socket)

  plug(Plug.Static, at: "/", from: :phoenix_test_playwright)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart],
    pass: ["*/*"]
  )

  plug(Plug.MethodOverride)
  plug(Plug.Session, @session_options)
  plug(PhoenixTest.Router)

  def session_options, do: @session_options
end

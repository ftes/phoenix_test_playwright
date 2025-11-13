import Config

config :esbuild,
  version: "0.25.9",
  default: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../../priv/static/assets),
    cd: Path.expand("../test/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :logger, level: :error

config :phoenix_test,
  endpoint: PhoenixTest.Endpoint,
  otp_app: :phoenix_test_playwright,
  playwright: [
    assets_dir: "priv/static/assets",
    headless: System.get_env("PW_HEADLESS", "true") in ~w(t true),
    screenshot: System.get_env("PW_SCREENSHOT", "false") in ~w(t true),
    trace: System.get_env("PW_TRACE", "false") in ~w(t true),
    timeout: String.to_integer(System.get_env("PW_TIMEOUT", "500")),
    browser_pool: :chromium_pool,
    browser_pools: [
      [id: :chromium_pool, browser: :chromium],
      [id: :firefox_pool, browser: :firefox]
    ]
  ]

config :phoenix_test_playwright, PhoenixTest.Endpoint,
  server: true,
  http: [port: 4002],
  live_view: [signing_salt: "112345678212345678312345678412"],
  secret_key_base: String.duplicate("57689", 50),
  pubsub_server: PhoenixTest.PubSub,
  render_errors: [
    formats: [html: PhoenixTest.WebApp.ErrorView],
    layout: false
  ]

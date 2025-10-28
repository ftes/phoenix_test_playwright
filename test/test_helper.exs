ExUnit.start(capture_log: true)

{:ok, _} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: PhoenixTest.PubSub},
      {PhoenixTest.Playwright.BrowserPool, name: :chromium, size: System.schedulers_online(), browser: :chromium}
    ],
    strategy: :one_for_one
  )

{:ok, _} = PhoenixTest.Endpoint.start_link()

Application.put_env(:phoenix_test, :base_url, PhoenixTest.Endpoint.url())

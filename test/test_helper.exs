ExUnit.start(capture_log: true)

{:ok, _} =
  Supervisor.start_link(
    [
      {Registry, keys: :unique, name: PhoenixTest.Playwright.BrowserPool.Registry},
      {DynamicSupervisor, name: PhoenixTest.Playwright.BrowserPool.Supervisor, strategy: :one_for_one},
      {Phoenix.PubSub, name: PhoenixTest.PubSub}
    ],
    strategy: :one_for_one
  )

{:ok, _} = PhoenixTest.Endpoint.start_link()

Application.put_env(:phoenix_test, :base_url, PhoenixTest.Endpoint.url())

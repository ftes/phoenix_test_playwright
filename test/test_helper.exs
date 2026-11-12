alias PhoenixTest.WebApp.Endpoint

ExUnit.start(capture_log: false)

{:ok, _} = PhoenixTest.Playwright.Repo.start_link()
{:ok, _} = Supervisor.start_link([{Phoenix.PubSub, name: PhoenixTest.PubSub}], strategy: :one_for_one)
{:ok, _} = Endpoint.start_link()

base_url = System.get_env("BASE_URL", Endpoint.url())
Application.put_env(:phoenix_test, :base_url, base_url)

# Only starts a driver with `ws_endpoint` (`mix test.websocket`): `PlaywrightEx.Test.BrowserPool` runs local browsers.
{:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()

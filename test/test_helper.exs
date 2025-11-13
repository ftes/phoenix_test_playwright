alias PhoenixTest.Endpoint

ExUnit.start(capture_log: true)

{:ok, _} = Supervisor.start_link([{Phoenix.PubSub, name: PhoenixTest.PubSub}], strategy: :one_for_one)
{:ok, _} = Endpoint.start_link()
{:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()

Application.put_env(:phoenix_test, :base_url, Endpoint.url())

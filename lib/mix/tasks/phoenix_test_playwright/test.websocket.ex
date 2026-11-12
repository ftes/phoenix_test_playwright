defmodule Mix.Tasks.PhoenixTestPlaywright.Test.Websocket do
  @moduledoc false

  # Contributor-only: runs the test suite against a Playwright server running in a Docker
  # container, connected via websocket transport. This tests the websocket transport path
  # without requiring locally installed browsers.
  #
  #     mix phoenix_test_playwright.test.websocket
  #     mix phoenix_test_playwright.test.websocket --warnings-as-errors
  #     mix phoenix_test_playwright.test.websocket test/specific_test.exs
  #
  # All arguments are passed through to `mix test`.

  use Mix.Task

  # `:test`-only deps not available when running `mix docs` in `:dev` env
  @compile {:no_warn_undefined, [Testcontainers, Testcontainers.Container, Testcontainers.LogWaitStrategy]}

  @impl Mix.Task
  def run(args) do
    # Start testcontainers (transitively starts tesla, hackney, etc.)
    {:ok, _} = Application.ensure_all_started(:testcontainers)
    {:ok, _} = Testcontainers.start()

    playwright_version = PlaywrightEx.Driver.version()
    playwright_image = "mcr.microsoft.com/playwright:v#{playwright_version}-noble"

    container_config =
      playwright_image
      |> Testcontainers.Container.new()
      |> Testcontainers.Container.with_exposed_port(3000)
      |> Testcontainers.Container.with_cmd(
        ~w(npx --yes playwright@#{playwright_version} run-server --port 3000 --host 0.0.0.0)
      )
      # Docker's port forward accepts connections before the server listens, and `connect` doesn't retry.
      |> Testcontainers.Container.with_waiting_strategy(Testcontainers.LogWaitStrategy.new(~r/Listening on/, 60_000))

    {:ok, container} = Testcontainers.start_container(container_config)

    host_port = Testcontainers.Container.mapped_port(container, 3000)
    ws_endpoint = "ws://localhost:#{host_port}"

    # Connect PlaywrightEx.Test.BrowserPool's browsers to the container
    test_config =
      :playwright_ex
      |> Application.get_env(:test, [])
      |> Keyword.put(:connect_options, ws_endpoint: ws_endpoint)

    Application.put_env(:playwright_ex, :test, test_config)

    # Set base_url so container can reach the Phoenix server
    docker_host = docker_host_address()
    port = Application.get_env(:phoenix_test_playwright, PhoenixTest.WebApp.Endpoint)[:http][:port]
    System.put_env("BASE_URL", "http://#{docker_host}:#{port}")

    Mix.Task.run("test", args ++ ["--exclude", "skip_websocket"])
  end

  defp docker_host_address do
    case :os.type() do
      {:unix, :darwin} ->
        "host.docker.internal"

      {:unix, :linux} ->
        case System.cmd("docker", [
               "network",
               "inspect",
               "bridge",
               "--format",
               "{{range .IPAM.Config}}{{.Gateway}}{{end}}"
             ]) do
          {gateway, 0} -> String.trim(gateway)
          _ -> "172.17.0.1"
        end

      _ ->
        "host.docker.internal"
    end
  end
end

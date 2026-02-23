defmodule Mix.Tasks.PhoenixTestPlaywright.Test.Websocket do
  @shortdoc "Runs tests using a containerized Playwright server via websocket"
  @moduledoc """
  Runs the test suite against a Playwright server running in a Docker container,
  connected via websocket transport.

  This is useful for testing the websocket transport path without requiring a
  local Playwright installation.

  ## Usage

      mix phoenix_test_playwright.test.websocket
      mix phoenix_test_playwright.test.websocket --warnings-as-errors
      mix phoenix_test_playwright.test.websocket test/specific_test.exs

  All arguments are passed through to `mix test`.
  """

  use Mix.Task

  # `:test`-only deps not available when running `mix docs` in `:dev` env
  @compile {:no_warn_undefined, [Testcontainers, Testcontainers.Container, Testcontainers.PortWaitStrategy]}

  @impl Mix.Task
  def run(args) do
    # Start testcontainers (transitively starts tesla, hackney, etc.)
    {:ok, _} = Application.ensure_all_started(:testcontainers)
    {:ok, _} = Testcontainers.start()

    playwright_version = playwright_version_from_lock_file()
    playwright_image = "mcr.microsoft.com/playwright:v#{playwright_version}-noble"

    container_config =
      playwright_image
      |> Testcontainers.Container.new()
      |> Testcontainers.Container.with_exposed_port(3000)
      |> Testcontainers.Container.with_cmd(
        ~w(npx -y playwright@#{playwright_version} run-server --port 3000 --host 0.0.0.0)
      )
      |> Testcontainers.Container.with_waiting_strategy(Testcontainers.PortWaitStrategy.new("localhost", 3000, 30_000))

    {:ok, container} = Testcontainers.start_container(container_config)

    host_port = Testcontainers.Container.mapped_port(container, 3000)
    ws_endpoint = "ws://localhost:#{host_port}"

    # Update playwright config with ws_endpoint
    playwright_config =
      :phoenix_test
      |> Application.get_env(:playwright, [])
      |> Keyword.put(:ws_endpoint, ws_endpoint)
      |> Keyword.put(:browser_pool, false)

    Application.put_env(:phoenix_test, :playwright, playwright_config)

    # Set base_url so container can reach the Phoenix server
    docker_host = docker_host_address()
    port = Application.get_env(:phoenix_test_playwright, PhoenixTest.Endpoint)[:http][:port]
    System.put_env("BASE_URL", "http://#{docker_host}:#{port}")

    Mix.Task.run("test", args ++ ["--exclude", "skip_websocket"])
  end

  defp playwright_version_from_lock_file do
    :phoenix_test
    |> Application.fetch_env!(:playwright)
    |> Keyword.fetch!(:assets_dir)
    |> Path.join("package-lock.json")
    |> File.read!()
    |> JSON.decode!()
    |> get_in(~w(packages node_modules/playwright version))
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

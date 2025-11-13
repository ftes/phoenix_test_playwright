defmodule PhoenixTest.Playwright.Connection do
  @moduledoc """
  Stateful, `:gen_statem` based connection to a Playwright node.js server.
  The connection is established via `PhoenixTest.Playwright.PortServer`.

  States:
  - `:pending`: Initial state, waiting for Playwright initialization. Post calls are postponed.
  - `:started`: Playwright is ready, all operations are processed normally.

  You won't usually have to use this module directly.
  `PhoenixTest.Playwright` uses this under the hood.
  """
  @behaviour :gen_statem

  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.PortServer

  @timeout_grace_factor 1.5
  @min_genserver_timeout to_timeout(second: 1)

  defstruct initializers: %{},
            guid_subscribers: %{},
            posts_in_flight: %{}

  @name __MODULE__

  @doc false
  def child_spec([]) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
  end

  @doc false
  def start_link do
    :gen_statem.start_link({:local, @name}, __MODULE__, :no_init_arg, timeout: Config.global(:timeout))
  end

  @doc false
  def child_spec([]) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
  end

  @doc """
  Launch a browser and return its `guid`.
  """
  def launch_browser(type, opts) do
    types = initializer("Playwright")
    type_id = Map.fetch!(types, type).guid
    timeout = opts[:browser_launch_timeout] || opts[:timeout] || Config.global(:browser_launch_timeout)
    params = opts |> Map.new() |> Map.put(:timeout, timeout)

    case post(guid: type_id, method: :launch, params: params) do
      %{result: %{browser: %{guid: guid}}} -> guid
      %{error: %{error: %{name: "TimeoutError"} = error}} -> raise launch_timeout_error_msg(type, error)
    end
  end

  @doc """
  Subscribe to messages for a guid and its descendants.
  """
  def subscribe(pid \\ self(), guid) do
    :gen_statem.cast(@name, {:subscribe, pid, guid})
  end

  @doc false
  def handle_playwright_msg(msg) do
    :gen_statem.cast(@name, {:msg, msg})
  end

  @doc """
  Post a message and await the response.
  Wait for an additional grace period after the playwright timeout.
  """
  def post(msg, timeout \\ nil) do
    msg =
      msg
      |> Enum.into(%{params: %{}, metadata: %{}})
      |> update_in(~w(params timeout)a, &(&1 || timeout || Config.global(:timeout)))
      |> Map.put_new_lazy(:id, fn -> System.unique_integer([:positive, :monotonic]) end)

    call_timeout = max(@min_genserver_timeout, round(msg.params.timeout * @timeout_grace_factor))

    :gen_statem.call(@name, {:post, msg}, call_timeout)
  end

  @doc """
  Get the initializer data for a channel.
  """
  def initializer(guid) do
    :gen_statem.call(@name, {:initializer, guid})
  end

  @impl :gen_statem
  def callback_mode, do: :state_functions

  @impl :gen_statem
  def init(:no_init_arg) do
    {:ok, _port_server} = PortServer.start_link(self())
    msg = %{guid: "", params: %{sdk_language: :javascript}, method: :initialize, metadata: %{}}
    PortServer.post(msg)

    {:ok, :pending, %__MODULE__{}}
  end

  @doc false
  def pending(:cast, {:msg, %{method: :__create__, params: %{guid: "Playwright"}} = msg}, data) do
    {:next_state, :started, add_initializer(data, msg)}
  end

  def pending(:cast, _msg, _data), do: {:keep_state_and_data, [:postpone]}
  def pending({:call, _from}, _msg, _data), do: {:keep_state_and_data, [:postpone]}

  @doc false
  def started({:call, from}, {:post, msg}, data) do
    PortServer.post(msg)
    {:keep_state, put_in(data.posts_in_flight[msg.id], from)}
  end

  def started({:call, from}, {:initializer, guid}, data) do
    {:keep_state_and_data, [{:reply, from, Map.fetch!(data.initializers, guid)}]}
  end

  def started(:cast, {:subscribe, recipient, guid}, data) do
    {:keep_state, update_in(data.guid_subscribers[guid], &[recipient | &1 || []])}
  end

  def started(:cast, {:msg, %{method: :page_error} = msg}, _data) do
    if module = Config.global(:js_logger) do
      module.log(:error, msg.params.error, msg)
    end

    :keep_state_and_data
  end

  def started(:cast, {:msg, %{method: :console} = msg}, _data) do
    if module = Config.global(:js_logger) do
      level = log_level_from_js(msg[:params][:type])
      module.log(level, msg.params.text, msg)
    end

    :keep_state_and_data
  end

  def started(:cast, {:msg, msg}, data) when is_map_key(data.posts_in_flight, msg.id) do
    {from, posts_in_flight} = Map.pop(data.posts_in_flight, msg.id)
    :gen_statem.reply(from, msg)

    {:keep_state, %{data | posts_in_flight: posts_in_flight}}
  end

  def started(:cast, {:msg, msg}, data) do
    {:keep_state, data |> add_initializer(msg) |> notify_subscribers(msg)}
  end

  defp add_initializer(data, %{method: :__create__} = msg) do
    put_in(data.initializers[msg.params.guid], msg.params.initializer)
  end

  defp add_initializer(data, _msg), do: data

  defp notify_subscribers(data, msg) when is_map_key(data.guid_subscribers, msg.guid) do
    for pid <- Map.fetch!(data.guid_subscribers, msg.guid), do: send(pid, {:playwright_msg, msg})
    data
  end

  defp notify_subscribers(data, _msg), do: data

  defp launch_timeout_error_msg(type, error) do
    %{stack: stack, message: message} = error

    """
    Timed out while launching the Playwright browser, #{String.capitalize("#{type}")}. #{message}

    You may need to increase the :browser_launch_timeout option in config/test.exs:

        config :phoenix_test,
          playwright: [
            browser_launch_timeout: 10_000,
            # other Playwright options...
          ],
          # other phoenix_test options...

    Playwright backtrace:

    #{stack}
    """
  end

  defp log_level_from_js("error"), do: :error
  defp log_level_from_js("debug"), do: :debug
  defp log_level_from_js(_), do: :info
end

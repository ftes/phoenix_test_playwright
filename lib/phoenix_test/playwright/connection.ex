defmodule PhoenixTest.Playwright.Connection do
  @moduledoc """
  Stateful, `GenServer` based connection to a Playwright node.js server.
  The connection is established via `PhoenixTest.Playwright.Port`.

  The state is ever-growing and  never pruned.
  Since we're dealing with (short-lived) tets, that is considered good enough for now.

  The state includes
  - a tree of Playwright artifact guids,
  - all received messages,
  - sent message for which we're expecting a response.

  You won't usually have to use this module directly.
  `PhoenixTest.Playwright` uses this under the hood.
  """
  use GenServer

  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.Port, as: PlaywrightPort

  require Logger

  @timeout_grace_factor 1.5
  @min_genserver_timeout to_timeout(second: 1)

  defstruct [
    :port,
    status: :pending,
    awaiting_started: [],
    initializers: %{},
    guid_ancestors: %{},
    guid_subscribers: %{},
    guid_received: %{},
    posts_in_flight: %{}
  ]

  @name __MODULE__

  def start_link do
    GenServer.start_link(__MODULE__, :no_init_arg, name: @name, timeout: Config.global(:timeout))
  end

  @doc """
  Lazy launch. Only start the playwright server if actually needed by a test.
  """
  def ensure_started do
    case Process.whereis(@name) do
      nil -> start_link()
      pid -> {:ok, pid}
    end

    GenServer.call(@name, :awaiting_started)
  end

  @doc """
  Launch a browser and return its `guid`.
  """
  def launch_browser(type, opts) do
    types = initializer("Playwright")
    type_id = Map.fetch!(types, type).guid
    resp = post(guid: type_id, method: :launch, params: Map.new(opts))
    resp.result.browser.guid
  end

  @doc """
  Subscribe to messages for a guid and its descendants.
  """
  def subscribe(pid \\ self(), guid) do
    GenServer.cast(@name, {:subscribe, {pid, guid}})
  end

  @doc """
  Post a message and await the response.
  We wait for an additional grace period after the timeout that we pass to playwright.
  """
  def post(msg, timeout \\ nil) do
    default = %{params: %{}, metadata: %{}}
    msg = msg |> Enum.into(default) |> update_in(~w(params timeout)a, &(&1 || timeout || Config.global(:timeout)))
    call_timeout = max(@min_genserver_timeout, round(msg.params.timeout * @timeout_grace_factor))
    GenServer.call(@name, {:post, msg}, call_timeout)
  end

  @doc """
  Get all past received messages for a playwright `guid` (e.g. a `PhoenixTest.Playwright.Frame`).
  """
  def received(guid) do
    GenServer.call(@name, {:received, guid})
  end

  @doc """
  Get the initializer data for a channel.
  """
  def initializer(guid) do
    GenServer.call(@name, {:initializer, guid})
  end

  @impl GenServer
  def init(:no_init_arg) do
    port = PlaywrightPort.open()
    msg = %{guid: "", params: %{sdk_language: :javascript}, method: :initialize, metadata: %{}}
    PlaywrightPort.post(port, msg)

    {:ok, %__MODULE__{port: port}}
  end

  @impl GenServer
  def handle_cast({:subscribe, {recipient, guid}}, state) do
    subscribers = Map.update(state.guid_subscribers, guid, [recipient], &[recipient | &1])
    {:noreply, %{state | guid_subscribers: subscribers}}
  end

  @impl GenServer
  def handle_call({:post, msg}, from, state) do
    msg_id = fn -> System.unique_integer([:positive, :monotonic]) end
    msg = msg |> Map.new() |> Map.put_new_lazy(:id, msg_id)
    PlaywrightPort.post(state.port, msg)

    {:noreply, Map.update!(state, :posts_in_flight, &Map.put(&1, msg.id, from))}
  end

  def handle_call({:received, guid}, _from, state) do
    {:reply, Map.get(state.guid_received, guid, []), state}
  end

  def handle_call({:initializer, guid}, _from, state) do
    {:reply, Map.get(state.initializers, guid), state}
  end

  def handle_call(:awaiting_started, from, %{status: :pending} = state) do
    {:noreply, Map.update!(state, :awaiting_started, &[from | &1])}
  end

  def handle_call(:awaiting_started, _from, %{status: :started} = state) do
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({_, {:data, _}} = raw_msg, state) do
    {port, msgs} = PlaywrightPort.parse(state.port, raw_msg)
    state = %{state | port: port}
    state = Enum.reduce(msgs, state, &handle_recv/2)

    {:noreply, state}
  end

  defp handle_recv(msg, state) do
    state
    |> log_js_error(msg)
    |> log_console(msg)
    |> add_guid_ancestors(msg)
    |> add_initializer(msg)
    |> add_received(msg)
    |> handle_started(msg)
    |> reply_in_flight(msg)
    |> notify_subscribers(msg)
  end

  defp log_js_error(state, %{method: :page_error} = msg) do
    Logger.error("Javascript error: #{inspect(msg.params.error)}")
    state
  end

  defp log_js_error(state, _), do: state

  defp log_console(state, %{method: :console} = msg) do
    case Config.global(:js_logger) do
      :default ->
        level =
          case msg.params.type do
            "error" -> :error
            "debug" -> :debug
            _ -> :info
          end

        Logger.log(level, "Javascript console: #{msg.params.text}")

      fun when is_function(fun, 1) ->
        fun.(msg)

      nil ->
        nil

      false ->
        nil
    end

    state
  end

  defp log_console(state, _), do: state

  defp handle_started(state, %{method: :__create__, params: %{type: "Playwright"}}) do
    for from <- state.awaiting_started, do: GenServer.reply(from, :ok)
    %{state | status: :started, awaiting_started: :none}
  end

  defp handle_started(state, _), do: state

  defp add_guid_ancestors(state, %{method: :__create__} = msg) do
    child = msg.params.guid
    parent = msg.guid
    parent_ancestors = Map.get(state.guid_ancestors, parent, [])

    Map.update!(state, :guid_ancestors, &Map.put(&1, child, [parent | parent_ancestors]))
  end

  defp add_guid_ancestors(state, _), do: state

  defp add_initializer(state, %{method: :__create__} = msg) do
    Map.update!(state, :initializers, &Map.put(&1, msg.params.guid, msg.params.initializer))
  end

  defp add_initializer(state, _), do: state

  defp reply_in_flight(%{posts_in_flight: in_flight} = state, msg) when is_map_key(in_flight, msg.id) do
    {from, in_flight} = Map.pop(in_flight, msg.id)
    GenServer.reply(from, msg)

    %{state | posts_in_flight: in_flight}
  end

  defp reply_in_flight(state, _), do: state

  defp add_received(state, %{guid: guid} = msg) do
    update_in(state.guid_received[guid], &[msg | &1 || []])
  end

  defp add_received(state, _), do: state

  defp notify_subscribers(state, %{guid: guid} = msg) do
    for guid <- [guid | Map.get(state.guid_ancestors, guid, [])],
        pid <- Map.get(state.guid_subscribers, guid, []) do
      send(pid, {:playwright, msg})
    end

    state
  end

  defp notify_subscribers(state, _), do: state
end

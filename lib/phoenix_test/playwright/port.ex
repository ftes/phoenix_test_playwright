defmodule PhoenixTest.Playwright.Port do
  @moduledoc """
  Start a Playwright node.js server and communicate with it via a `Port`.

  A single `Port` response can contain multiple Playwright messages and/or a fraction of a message.
  The remaining fraction is stored in `buffer` and continiued in the next `Port` response.
  """

  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.Serialization

  defstruct [
    :port,
    :remaining,
    :buffer
  ]

  def open do
    port =
      Port.open({:spawn_executable, Config.global(:runner)}, [
        :binary,
        args: ["playwright", "run-driver"],
        cd: Config.global(:assets_dir)
      ])

    %__MODULE__{port: port, remaining: 0, buffer: ""}
  end

  def post(state, msg) do
    frame = to_json(msg)
    length = byte_size(frame)
    padding = <<length::utf32-little>>

    Port.command(state.port, padding <> frame)
  end

  def parse(%{port: port} = state, {port, {:data, data}}) do
    {remaining, buffer, frames} = parse(data, state.remaining, state.buffer, [])
    state = %{state | buffer: buffer, remaining: remaining}
    msgs = Enum.map(frames, &from_json/1)

    {state, msgs}
  end

  defp parse(data, remaining, buffer, frames)

  defp parse(<<head::unsigned-little-integer-size(32)>>, 0, "", frames) do
    {head, "", frames}
  end

  defp parse(<<head::unsigned-little-integer-size(32), data::binary>>, 0, "", frames) do
    parse(data, head, "", frames)
  end

  defp parse(<<data::binary>>, remaining, buffer, frames) when byte_size(data) == remaining do
    {0, "", frames ++ [buffer <> data]}
  end

  defp parse(<<data::binary>>, remaining, buffer, frames) when byte_size(data) > remaining do
    <<frame::size(remaining)-binary, tail::binary>> = data
    parse(tail, 0, "", frames ++ [buffer <> frame])
  end

  defp parse(<<data::binary>>, remaining, buffer, frames) when byte_size(data) < remaining do
    {remaining - byte_size(data), buffer <> data, frames}
  end

  def to_json(msg) do
    msg
    |> Map.update(:method, nil, &Serialization.camelize/1)
    |> Serialization.deep_key_camelize()
    |> Phoenix.json_library().encode!()
  end

  def from_json(frame) do
    frame
    |> Phoenix.json_library().decode!()
    |> Serialization.deep_key_underscore()
    |> Map.update(:method, nil, &Serialization.underscore/1)
  end
end

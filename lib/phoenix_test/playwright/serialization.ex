defmodule PhoenixTest.Playwright.Serialization do
  @moduledoc false

  require Logger

  def camelize(input), do: input |> to_string() |> Phoenix.Naming.camelize(:lower)
  def underscore(string), do: string |> Phoenix.Naming.underscore() |> String.to_atom()

  def deep_key_camelize(input), do: deep_key_transform(input, &camelize/1)
  def deep_key_underscore(input), do: deep_key_transform(input, &underscore/1)

  def serialize_arg(nil) do
    %{value: %{v: "undefined"}, handles: []}
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def deserialize_arg(value) do
    case value do
      {:ok, value} ->
        deserialize_arg(value)

      list when is_list(list) ->
        Enum.map(list, &deserialize_arg/1)

      %{a: list} ->
        Enum.map(list, &deserialize_arg/1)

      %{b: boolean} ->
        boolean

      %{n: number} ->
        number

      %{o: object} ->
        Map.new(object, fn item -> {item.k, deserialize_arg(item.v)} end)

      %{s: string} ->
        string

      %{v: "null"} ->
        nil

      %{v: "undefined"} ->
        nil

      %{ref: _} ->
        :ref_not_resolved
    end
  end

  defp deep_key_transform(input, fun) when is_function(fun, 1) do
    case input do
      list when is_list(list) ->
        Enum.map(list, &deep_key_transform(&1, fun))

      map when is_map(map) ->
        Map.new(map, fn
          {k, v} when is_map(v) ->
            {fun.(k), deep_key_transform(v, fun)}

          {k, list} when is_list(list) ->
            {fun.(k), Enum.map(list, fn v -> deep_key_transform(v, fun) end)}

          {k, v} ->
            {fun.(k), v}
        end)

      other ->
        other
    end
  end
end

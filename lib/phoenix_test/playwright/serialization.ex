defmodule PhoenixTest.Playwright.Serialization do
  @moduledoc false

  require Logger

  def serialize(nil) do
    %{value: %{v: "undefined"}, handles: []}
  end

  def deserialize({:ok, value}) do
    deserialize(value)
  end

  def deserialize(value) when is_map(value) do
    case value do
      %{a: list} ->
        Enum.map(list, &deserialize/1)

      %{b: boolean} ->
        boolean

      %{n: number} ->
        number

      %{o: object} ->
        object
        |> Map.new(fn item -> {item.k, deserialize(item.v)} end)
        |> deep_atomize_keys()

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

  def deserialize(value) when is_list(value) do
    Enum.map(value, &deserialize(&1))
  end

  defp deep_atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_map(v) ->
        {to_atom(k), deep_atomize_keys(v)}

      {k, list} when is_list(list) ->
        {to_atom(k), Enum.map(list, fn v -> deep_atomize_keys(v) end)}

      {k, v} ->
        {to_atom(k), v}
    end)
  end

  defp deep_atomize_keys(other), do: other

  defp to_atom(nil), do: raise(ArgumentError, message: "Unable to convert nil into an atom")
  defp to_atom(s) when is_binary(s), do: String.to_atom(s)
  defp to_atom(a) when is_atom(a), do: a

  def camel_case_keys(enum) when is_map(enum) or is_list(enum) do
    Map.new(enum, fn {key, value} -> {camelize(key) |> String.to_atom(), value} end)
  end

  defp camelize(key) when is_atom(key) do
    key
    |> to_string()
    |> camelize()
  end

  # Taken from Phoenix.Naming.camelize(binary, :lower)
  defp camelize(""), do: ""
  defp camelize(<<?_, t::binary>>), do: camelize(t)

  defp camelize(<<h, _t::binary>> = value) do
    <<_first, rest::binary>> = Macro.camelize(value)
    <<to_lower_char(h)>> <> rest
  end

  # Taken from Phoenix.Naming.to_lower_char/1
  defp to_lower_char(char) when char in ?A..?Z, do: char + 32
  defp to_lower_char(char), do: char
end

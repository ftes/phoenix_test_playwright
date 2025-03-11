defmodule PhoenixTest.Playwright.Cookies do
  @moduledoc """
  Functions to assist with adding cookies to the browser context

  Note that a cookie's value must be a binary unless the cookie is signed/encrypted

  ## Cookie fields

  | key          | type        | description |
  | -----------  | ----------- | ----------- |
  | `:name`      | `binary()`  | |
  | `:value`     | `binary()`  | |
  | `:url`       | `binary()`  | *(optional)* either url or domain / path are required |
  | `:domain`    | `binary()`  | *(optional)* either url or domain / path are required |
  | `:path`      | `binary()`  | *(optional)* either url or domain / path are required |
  | `:expires`   | `float()`   | *(optional)* Unix time in seconds. |
  | `:http_only` | `boolean()` | *(optional)* |
  | `:secure`    | `boolean()` | *(optional)* |
  | `:same_site` | `binary()`  | *(optional)* one of "Strict", "Lax", "None" |
  """
  @type cookie :: %{
          :name => binary(),
          :value => binary(),
          :url => binary(),
          :domain => binary(),
          :path => binary(),
          :expires => float(),
          :http_only => boolean(),
          :secure => boolean(),
          :same_site => binary()
        }

  @doc """
  Converts the atom-keyed cookie map into a string-keyed map suitable for posting
  """
  def to_params_map(cookie) do
    cookie
    |> ensure_binary_cookie_value()
    |> transform_to_camel_case_params_map()
  end

  defp ensure_binary_cookie_value(%{value: _value} = cookie) do
    Map.update!(cookie, :value, fn value ->
      secret_key_base = Application.get_env(:phoenix_test_playwright, PhoenixTest.Endpoint)[:secret_key_base]

      opts =
        cookie
        |> Map.take([:domain, :max_age, :path, :http_only, :secure, :extra, :sign, :encrypt, :same_site])
        |> Map.to_list()

      plug_cookie =
        Plug.Conn.put_resp_cookie(%Plug.Conn{secret_key_base: secret_key_base}, to_string(cookie.name), value, opts)

      plug_cookie.resp_cookies[cookie.name].value
    end)
  end

  defp ensure_binary_cookie_value(cookie) do
    cookie
  end

  defp transform_to_camel_case_params_map(cookie) do
    Enum.reduce(cookie, %{}, fn {key, val}, acc ->
      string_key = key |> to_string() |> Macro.camelize() |> downcase_first()
      Map.put(acc, string_key, val)
    end)
  end

  def downcase_first(<<first::utf8, rest::binary>>) do
    String.downcase(<<first::utf8>>) <> rest
  end
end

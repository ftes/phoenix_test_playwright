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
    Map.update(cookie, :value, "", fn value ->
      otp_app = Application.get_env(:phoenix_test, :otp_app)
      endpoint = Application.get_env(:phoenix_test, :endpoint)
      secret_key_base = Application.get_env(otp_app, endpoint)[:secret_key_base]

      opts =
        cookie
        |> Map.take([:domain, :max_age, :path, :http_only, :secure, :extra, :sign, :encrypt, :same_site])
        |> Map.to_list()

      plug_cookie =
        Plug.Conn.put_resp_cookie(%Plug.Conn{secret_key_base: secret_key_base}, to_string(cookie.name), value, opts)

      plug_cookie.resp_cookies[cookie.name].value
    end)
  end

  def to_session_params_map(cookie, session_options) do
    cookie
    |> Map.update(:value, "", fn value ->
      otp_app = Application.get_env(:phoenix_test, :otp_app)
      endpoint = Application.get_env(:phoenix_test, :endpoint)
      secret_key_base = Application.get_env(otp_app, endpoint)[:secret_key_base]

      %Plug.Conn{secret_key_base: secret_key_base, owner: self()}
      |> Plug.Session.call(Plug.Session.init(session_options))
      |> Plug.Conn.fetch_session()
      |> then(fn conn ->
        Enum.reduce(value, conn, fn {key, val}, conn ->
          Plug.Conn.put_session(conn, key, val)
        end)
      end)
      |> Plug.Conn.fetch_cookies(signed: [session_options[:key]])
      |> Map.update!(:adapter, fn {_adapter, nil} ->
        {PhoenixTest.Playwright.Cookies.PseudoAdapter, nil}
      end)
      |> Plug.Conn.send_resp(200, "")
      |> Map.get(:cookies)
      |> Map.get(session_options[:key])
    end)
    |> Map.update(:name, session_options[:key], & &1)
  end
end

defmodule PhoenixTest.Playwright.Cookies.PseudoAdapter do
  @moduledoc false
  def send_resp(_, _, _, _) do
    {:ok, "", ""}
  end
end

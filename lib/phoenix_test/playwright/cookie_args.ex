defmodule PhoenixTest.Playwright.CookieArgs do
  @moduledoc """
  Functions to assist with adding cookies to the browser context

  A cookie's value must be a binary unless the cookie is signed/encrypted

  ## Cookie fields

  | key          | type        | description |
  | -----------  | ----------- | ----------- |
  | `:name`      | `binary()`  | |
  | `:value`     | `binary()`  | |
  | `:url`       | `binary()`  | *(optional)* either url or domain / path are required |
  | `:domain`    | `binary()`  | *(optional)* either url or domain / path are required |
  | `:path`      | `binary()`  | *(optional)* either url or domain / path are required |
  | `:max_age`   | `float()`   | *(optional)* The cookie max age, in seconds. |
  | `:http_only` | `boolean()` | *(optional)* |
  | `:secure`    | `boolean()` | *(optional)* |
  | `:encrypt`   | `boolean()` | *(optional)* |
  | `:sign`      | `boolean()` | *(optional)* |
  | `:same_site` | `binary()`  | *(optional)* one of "Strict", "Lax", "None" |

  Two of the cookie fields mean nothing to Playwright. These are:

  1. `:encrypt`
  2. `:sign`

  The `:max_age` cookie field means the same thing as documented in `Plug.Conn.put_resp_cookie/4`.
  The `:max_age` value is used to infer the correct `expires` value that Playwright requires.

  See https://playwright.dev/docs/api/class-browsercontext#browser-context-add-cookies
  """

  alias Plug.Conn
  alias Plug.Session

  @type cookie :: [
          {:domain, binary()}
          | {:encrypt, boolean()}
          | {:http_only, boolean()}
          | {:max_age, integer()}
          | {:name, binary()}
          | {:path, binary()}
          | {:same_site, binary()}
          | {:secure, boolean()}
          | {:sign, boolean()}
          | {:url, binary()}
          | {:value, binary() | map()}
        ]

  @type playwright_cookie_args :: %{
          :name => binary(),
          :value => binary(),
          optional(:domain) => binary(),
          optional(:expires) => integer(),
          optional(:http_only) => binary(),
          optional(:path) => binary(),
          optional(:same_site) => binary(),
          optional(:secure) => binary(),
          optional(:url) => binary()
        }

  @playwright_cookie_fields [:domain, :expires, :http_only, :name, :path, :same_site, :secure, :url, :value]

  @doc """
  Converts the cookie kw list into a map suitable for posting
  """
  @spec from_cookie(cookie()) :: playwright_cookie_args()
  def from_cookie(cookie) do
    cookie
    |> ensure_value_is_valid_plug_conn_cookie()
    |> ensure_url_or_domain_path()
    |> plug_cookie_fields_to_playwright_cookie_fields()
  end

  @doc """
  Converts the session cookie kw list (with value that is a map) into a map suitable for posting
  """
  @spec from_session_options(cookie(), Keyword.t()) :: playwright_cookie_args()
  def from_session_options(cookie, session_options) do
    cookie
    |> ensure_value_is_valid_session_cookie(session_options)
    |> ensure_session_cookie_name(session_options)
    |> ensure_url_or_domain_path()
    |> plug_cookie_fields_to_playwright_cookie_fields()
  end

  defp ensure_value_is_valid_plug_conn_cookie(cookie) do
    Keyword.update(cookie, :value, "", fn value ->
      otp_app = Application.get_env(:phoenix_test, :otp_app)
      endpoint = Application.get_env(:phoenix_test, :endpoint)
      secret_key_base = Application.get_env(otp_app, endpoint)[:secret_key_base]

      opts = Keyword.take(cookie, [:domain, :encrypt, :extra, :http_only, :max_age, :path, :secure, :sign, :same_site])
      name = cookie[:name]

      plug_cookie =
        Conn.put_resp_cookie(%Conn{secret_key_base: secret_key_base}, name, value, opts)

      plug_cookie.resp_cookies[name].value
    end)
  end

  defp ensure_value_is_valid_session_cookie(cookie, session_options) do
    Keyword.update(cookie, :value, "", fn value ->
      name = session_options[:key]
      %Conn{cookies: %{^name => cookie_value}} = build_pseudo_conn_with_session(value, session_options)
      cookie_value
    end)
  end

  defp ensure_url_or_domain_path(cookie) do
    cond do
      cookie[:url] -> cookie
      cookie[:domain] && cookie[:path] -> cookie
      true -> Keyword.put(cookie, :url, Application.fetch_env!(:phoenix_test, :base_url))
    end
  end

  defp build_pseudo_conn_with_session(value, session_options) do
    otp_app = Application.get_env(:phoenix_test, :otp_app)
    endpoint = Application.get_env(:phoenix_test, :endpoint)
    secret_key_base = Application.get_env(otp_app, endpoint)[:secret_key_base]
    name = session_options[:key]

    %Conn{secret_key_base: secret_key_base, owner: self()}
    |> Session.call(Session.init(session_options))
    |> Conn.fetch_session()
    |> put_map_value_in_session(value)
    |> Conn.fetch_cookies(signed: [name], encrypted: [name])
    |> use_pseudo_adapter()
    |> Conn.send_resp(200, "")
  end

  defp put_map_value_in_session(plug_conn, value) do
    Enum.reduce(value, plug_conn, fn {key, val}, plug_conn ->
      Conn.put_session(plug_conn, key, val)
    end)
  end

  defp use_pseudo_adapter(plug_conn) do
    Map.update!(plug_conn, :adapter, fn {_adapter, nil} ->
      {PhoenixTest.Playwright.CookieArgs.PseudoAdapter, nil}
    end)
  end

  defp ensure_session_cookie_name(cookie, session_options) do
    Keyword.put_new(cookie, :name, session_options[:key])
  end

  defp plug_cookie_fields_to_playwright_cookie_fields(cookie) do
    cookie
    |> put_expires_if_max_age()
    |> Keyword.take(@playwright_cookie_fields)
    |> Map.new()
  end

  defp put_expires_if_max_age(cookie) do
    if max_age = Keyword.get(cookie, :max_age) do
      expires = DateTime.utc_now() |> DateTime.add(max_age) |> DateTime.to_unix()
      Keyword.put(cookie, :expires, expires)
    else
      cookie
    end
  end
end

defmodule PhoenixTest.Playwright.CookieArgs.PseudoAdapter do
  @moduledoc false
  def send_resp(_, _, _, _) do
    {:ok, "", ""}
  end
end

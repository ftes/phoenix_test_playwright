defmodule PhoenixTest.Playwright.CookieArgs do
  @moduledoc false

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
          optional(:httpOnly) => boolean(),
          optional(:path) => binary(),
          optional(:sameSite) => binary(),
          optional(:secure) => boolean(),
          optional(:url) => binary()
        }

  @playwright_cookie_fields [:domain, :expires, :http_only, :name, :path, :same_site, :secure, :url, :value]

  @doc """
  Converts the cookie kw list into a map suitable for posting
  """
  @spec from_cookie(cookie(), String.t() | nil) :: playwright_cookie_args()
  def from_cookie(cookie, base_url \\ nil) do
    cookie
    |> ensure_value_is_valid_plug_conn_cookie()
    |> ensure_url_or_domain_path(base_url)
    |> plug_cookie_fields_to_playwright_cookie_fields()
  end

  @doc """
  Converts the session cookie kw list (with value that is a map) into a map suitable for posting
  """
  @spec from_session_options(cookie(), Keyword.t(), String.t() | nil) :: playwright_cookie_args()
  def from_session_options(cookie, session_options, base_url \\ nil) do
    cookie
    |> ensure_value_is_valid_session_cookie(session_options)
    |> ensure_session_cookie_name(session_options)
    |> ensure_url_or_domain_path(base_url)
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
        Conn.put_resp_cookie(%Conn{secret_key_base: secret_key_base, remote_ip: {127, 0, 0, 1}}, name, value, opts)

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

  # Playwright takes a url, or a domain and path. Without a url or domain, a cookie goes to the
  # session's `base_url` (else phoenix_test's): its origin, as a url's path would scope the cookie
  # to it, or its host for a cookie with a path. A domain's path defaults to `/`.
  defp ensure_url_or_domain_path(cookie, base_url) do
    base_url = base_url || Application.fetch_env!(:phoenix_test, :base_url)

    cond do
      cookie[:url] -> cookie
      cookie[:domain] -> Keyword.put_new(cookie, :path, "/")
      cookie[:path] -> Keyword.put(cookie, :domain, URI.parse(base_url).host)
      true -> Keyword.put(cookie, :url, URI.to_string(%{URI.parse(base_url) | path: nil, query: nil, fragment: nil}))
    end
  end

  defp build_pseudo_conn_with_session(value, session_options) do
    otp_app = Application.get_env(:phoenix_test, :otp_app)
    endpoint = Application.get_env(:phoenix_test, :endpoint)
    secret_key_base = Application.get_env(otp_app, endpoint)[:secret_key_base]
    name = session_options[:key]

    %Conn{secret_key_base: secret_key_base, owner: self(), remote_ip: {127, 0, 0, 1}}
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
    |> Map.new(&playwright_cookie_field/1)
  end

  defp playwright_cookie_field({:http_only, value}), do: {:httpOnly, value}
  defp playwright_cookie_field({:same_site, value}), do: {:sameSite, normalize_same_site(value)}
  defp playwright_cookie_field(field), do: field

  defp normalize_same_site(value) when value in [:strict, "strict"], do: "Strict"
  defp normalize_same_site(value) when value in [:lax, "lax"], do: "Lax"
  defp normalize_same_site(value) when value in [:none, "none"], do: "None"
  defp normalize_same_site(value), do: value

  defp put_expires_if_max_age(cookie) do
    if max_age = Keyword.get(cookie, :max_age) do
      expires = DateTime.utc_now() |> DateTime.shift(second: max_age) |> DateTime.to_unix()
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

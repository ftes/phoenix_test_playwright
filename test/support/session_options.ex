defmodule PhoenixTest.SessionOptions do
  @moduledoc false
  def session_options do
    [
      store: :cookie,
      key: "_phoenix_test_key",
      signing_salt: "/VADsdfSfdMnp5"
    ]
  end
end

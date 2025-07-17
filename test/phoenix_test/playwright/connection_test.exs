defmodule PhoenixTest.Playwright.ConnectionTest do
  use ExUnit.Case, async: true

  alias PhoenixTest.Playwright.Connection

  setup_all do
    Connection.ensure_started()
  end

  test "launch_browser/2 produces a reasonable error on timeout" do
    for opts <- [
          %{browser_launch_timeout: -1_000},
          # :browser_launch_timeout overrides :timeout for this particular use case
          %{browser_launch_timeout: -1_000, timeout: 10_000},
          # :timeout is used as fallback if :browser_launch_timeout is not set
          %{timeout: -1_000}
        ] do
      try do
        Connection.launch_browser(:chromium, opts)
        flunk("Launch browser should have raised a timeout error")
      rescue
        error in RuntimeError ->
          assert error.message =~ "Timed out while launching the Playwright browser, Chromium."
          assert error.message =~ "You may need to increase the :browser_launch_timeout"
      end
    end
  end

  test "add_location/1 accepts unknown data" do
    message = %{a: 1}
    assert "Hi" == Connection.add_location("Hi", message)
  end

  test "add_location/1 adds the file location to console messages" do
    # a complete message
    message = %{
      params: %{
        args: [%{guid: "handle@2ae9bdee66c01d900097b961352f69f4"}],
        type: "log",
        location: %{
          url: "http://localhost:4002/assets/app.js",
          line_number: 7085,
          column_number: 10
        },
        text: "hello world",
        page: %{guid: "page@47f9839e9773e11062e7794049ae830c"}
      },
      method: :console,
      guid: "browser-context@6cb68e0f88cb4d3de5f56d4d91de65da"
    }

    assert "Hi (http://localhost:4002/assets/app.js:7085)" == Connection.add_location("Hi", message)

    file_not_found = %{
      params: %{
        args: [],
        type: "error",
        location: %{
          url: "http://localhost:4002/file.css",
          line_number: 0,
          column_number: 0
        },
        text: "Failed to load resource: the server responded with a status of 404 (Not Found)",
        page: %{guid: "page@7afde413c6394658641b41c790d79647"}
      },
      guid: "browser-context@a02c2c526d9615e458f0ad540722911d",
      method: :console
    }

    assert "Hi (http://localhost:4002/file.css)" == Connection.add_location("Hi", file_not_found)

    # shortend, line number 0
    message = %{
      params: %{
        type: "log",
        location: %{
          url: "http://localhost:4002/assets/app.js",
          line_number: 0
        },
        text: "hello world"
      },
      method: :console
    }

    assert "Hi (http://localhost:4002/assets/app.js)" == Connection.add_location("Hi", message)

    # shortend, line number 0
    message = %{
      params: %{
        type: "log",
        location: %{
          url: "http://localhost:4002/assets/app.js"
        },
        text: "hello world"
      },
      method: :console
    }

    assert "Hi (http://localhost:4002/assets/app.js)" == Connection.add_location("Hi", message)

    # shortend, line number 0, an error
    message = %{
      params: %{
        type: "log",
        location: %{
          url: "http://localhost:4002/assets/app.js",
          line_number: 0
        },
        text: "hello world"
      },
      method: :console
    }

    assert "Hi (http://localhost:4002/assets/app.js)" == Connection.add_location("Hi", message)

    # shortend, line number 0
    message = %{
      params: %{
        type: "log",
        location: %{
          url: ""
        },
        text: "hello world"
      },
      method: :console
    }

    assert "Hi" == Connection.add_location("Hi", message)
  end
end

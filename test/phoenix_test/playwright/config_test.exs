defmodule PhoenixTest.Playwright.ConfigTest do
  use ExUnit.Case, async: true

  alias PhoenixTest.Playwright.Config

  describe "browser_launch_opts" do
    test "accepts keyword list" do
      config = Config.validate!(browser_launch_opts: [args: ["--disable-gpu"]])
      assert config[:browser_launch_opts] == [args: ["--disable-gpu"]]
    end

    test "defaults to empty list" do
      config = Config.validate!([])
      assert config[:browser_launch_opts] == []
    end

    test "is included in setup_all_keys" do
      assert :browser_launch_opts in Config.setup_all_keys()
    end
  end
end

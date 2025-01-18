defmodule PhoenixTest.Playwright.SerializationTest do
  use ExUnit.Case, async: true
  alias PhoenixTest.Playwright.Serialization

  describe "camel_case_keys/1" do
    test "converts all keys to lower-case  camelCase" do
      camel_cased =
        Serialization.camel_case_keys(%{
          snake_case: "snake_case",
          PascalCase: :PascalCase,
          alreadyCamel: :alreadyCamel
        })

      assert camel_cased == %{
               snakeCase: "snake_case",
               pascalCase: :PascalCase,
               alreadyCamel: :alreadyCamel
             }
    end
  end
end

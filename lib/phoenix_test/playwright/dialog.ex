defmodule PhoenixTest.Playwright.Dialog do
  @moduledoc """
  Interact with a Playwright `Dialog`.

  There is no official documentation, since this is considered Playwright internal.

  References:
  - https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/client/dialog.ts
  """

  import PhoenixTest.Playwright.Connection, only: [post: 1]

  def accept(dialog_id, opts \\ []) do
    [guid: dialog_id, method: :accept, params: Map.new(opts)]
    |> post()
    |> unwrap_response(& &1)
  end

  def dismiss(dialog_id, opts \\ []) do
    [guid: dialog_id, method: :dismiss, params: Map.new(opts)]
    |> post()
    |> unwrap_response(& &1)
  end

  defp unwrap_response(response, fun) do
    case response do
      %{error: _} = error -> {:error, error}
      _ -> {:ok, fun.(response)}
    end
  end
end

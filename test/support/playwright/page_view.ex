defmodule PhoenixTest.Playwright.PageView do
  use Phoenix.Component

  def render("js_script_console_error.html", assigns) do
    ~H"""
    <script type="text/javascript">
      console.error("TESTME 42")
    </script>
    """
  end

  def render("data.html", assigns) do
    ~H"""
    <dl id={@id}>
      <%= for {key, value} <- @data do %>
        <dt>{key}:</dt> <dd>{value}</dd>
      <% end %>
    </dl>
    """
  end
end

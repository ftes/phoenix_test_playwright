defmodule PhoenixTest.Playwright.Live do
  @moduledoc false
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <h1>Playwright</h1>
    <a href="/pw/other">Navigate</a>
    <a data-confirm="Are you sure?" href="/pw/other">Confirm to navigate</a>

    <.form for={%{}} phx-change="validate" phx-submit="save">
      <input id="text-input" name="text" />
    </.form>

    <.form for={%{}} phx-submit="save">
      <label for="select-input">Select input</label>
      <select id="select-input" name="select" onkeydown="if (event.key === 'Enter') event.preventDefault()">
        <option value="one">One</option>
        <option value="two">Two</option>
      </select>
    </.form>

    <dl id="changed-form-data">
      <%= for {key, value} <- @changed_form_data do %>
        <dt>{key}:</dt> <dd>{value}</dd>
      <% end %>
    </dl>

    <dl id="submitted-form-data">
      <%= for {key, value} <- @submitted_form_data do %>
        <dt>{key}:</dt> <dd>{value}</dd>
      <% end %>
    </dl>

    <div id="drag-and-drop">
      <div id="drag-status">pending</div>
      <div id="drag-source" style="background: yellow;" draggable="true">Drag this</div>
      <div id="drag-target" style="border: 1px dashed black;" ondrop="document.getElementById('drag-status').innerHTML = 'dropped'">Drop here</div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {
      :ok,
      socket
      |> assign(:changed_form_data, %{})
      |> assign(:submitted_form_data, %{})
    }
  end

  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, :changed_form_data, params)}
  end

  def handle_event("save", params, socket) do
    {:noreply, assign(socket, :submitted_form_data, params)}
  end
end

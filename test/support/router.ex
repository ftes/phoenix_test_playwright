defmodule PhoenixTest.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
  end

  scope "/", PhoenixTest do
    pipe_through([:browser])

    post("/page/create_record", PageController, :create)
    put("/page/update_record", PageController, :update)
    delete("/page/delete_record", PageController, :delete)
    get("/page/unauthorized", PageController, :unauthorized)
    get("/page/redirect_to_static", PageController, :redirect_to_static)
    post("/page/redirect_to_liveview", PageController, :redirect_to_liveview)
    post("/page/redirect_to_static", PageController, :redirect_to_static)
    get("/page/cookies", PageController, :cookies)
    get("/page/session", PageController, :session)
    get("/page/:page", PageController, :show)

    live_session :live_pages, root_layout: {PhoenixTest.PageView, :layout} do
      live("/live/index", IndexLive)
      live("/live/page_2", Page2Live)
    end

    live("/live/index_no_layout", IndexLive)
    live("/live/redirect_on_mount/:redirect_type", RedirectLive)
  end
end

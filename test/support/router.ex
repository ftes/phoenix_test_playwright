defmodule PhoenixTest.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  alias PhoenixTest.Plugs.RequireCookiePlug
  alias PhoenixTest.Plugs.RequireSessionCookiePlug
  alias PhoenixTest.SessionOptions

  pipeline :setup_session do
    plug(Plug.Session, SessionOptions.session_options())
    plug(:fetch_session)
  end

  pipeline :browser do
    plug(:setup_session)
    plug(:accepts, ["html"])
    plug(:fetch_live_flash)
  end

  pipeline :cookie_protected do
    plug(RequireCookiePlug)
  end

  pipeline :session_protected do
    plug(RequireSessionCookiePlug)
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
    get("/page/:page", PageController, :show)

    live_session :live_pages, root_layout: {PhoenixTest.PageView, :layout} do
      live("/live/index", IndexLive)
      live("/live/page_2", Page2Live)
    end

    live("/live/index_no_layout", IndexLive)
    live("/live/redirect_on_mount/:redirect_type", RedirectLive)
  end

  scope "/", PhoenixTest do
    pipe_through([:browser, :cookie_protected])

    live_session :cookie_protected_live_pages, root_layout: {PhoenixTest.PageView, :layout} do
      live("/live/cookie_protected", IndexLive)
    end
  end

  scope "/", PhoenixTest do
    pipe_through([:browser, :session_protected])

    live_session :session_protected_live_pages, root_layout: {PhoenixTest.PageView, :layout} do
      live("/live/session_protected", IndexLive)
    end
  end
end

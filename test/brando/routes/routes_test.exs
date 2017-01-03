defmodule Brando.TestRouter do
  use Phoenix.Router
  import Brando.Users.Routes.Admin
  import Brando.Images.Routes.Admin
  import Brando.Villain.Routes.Admin
  import Brando.Dashboard.Routes.Admin

  pipeline :admin do
    plug :accepts, ~w(html json)
    plug :fetch_session
    plug :fetch_flash
    plug :put_layout, {Brando.Admin.LayoutView, "admin.html"}
    plug Guardian.Plug.VerifySession
    plug Guardian.Plug.LoadResource
    plug Guardian.Plug.EnsureAuthenticated, handler: Brando.AuthHandler
  end

  pipeline :browser do
    plug :accepts, ~w(html)
    plug :fetch_session
    plug :fetch_flash
  end

  pipeline :api do
    plug :accepts, ~w(json)
  end

  scope "/admin", as: :admin do
    pipe_through :admin
    dashboard_routes "/"
    user_routes "/users", Brando.Admin.UserController, private: %{schema: Brando.User}
    user_routes "/users2", private: %{schema: Brando.User}
    user_routes "/users3"
    image_routes "/images"
    image_routes "/images2", [image_schema: Brando.Image,
                              series_schema: Brando.ImageSeries,
                              category_schema: Brando.ImageCategory]

    scope "/villain" do
      villain_routes Brando.Admin.PostController
    end

    scope "/villain2" do
      villain_routes "/2", Brando.Admin.PostController
    end

    get "/", Brando.Admin.DashboardController, :dashboard
  end

  scope "/" do
    pipe_through :browser
    get "/login", Brando.SessionController, :login,
      private: %{schema: Brando.User,
                 layout: {Brando.Session.LayoutView, "auth.html"}}
    post "/login", Brando.SessionController, :login,
      private: %{schema: Brando.User,
                 layout: {Brando.Session.LayoutView, "auth.html"}}
    get "/logout", Brando.SessionController, :logout,
      private: %{schema: Brando.User,
                 layout: {Brando.Session.LayoutView, "auth.html"}}
  end
end

defmodule Brando.RoutesTest do
  use ExUnit.Case

  setup do
    routes =
      Phoenix.Router.ConsoleFormatter.format(Brando.TestRouter)
    {:ok, [routes: routes]}
  end

  test "user_routes", %{routes: routes} do
    assert routes =~ "/admin/users/new"
    assert routes =~ "/admin/users/:id/edit"
  end

  test "image_routes", %{routes: routes} do
    assert routes =~ "/admin/images/categories"
    assert routes =~ "/admin/images/categories/:id/edit"
  end

  test "villain_routes", %{routes: routes} do
    assert routes =~ "/admin/villain/villain/upload"
    assert routes =~ "/admin/villain/villain/browse"
    assert routes =~ "/admin/villain/villain/imagedata"

    assert routes =~ "/admin/villain2/2/villain/upload"
    assert routes =~ "/admin/villain2/2/villain/browse"
    assert routes =~ "/admin/villain2/2/villain/imagedata"
  end

  test "dashboard_routes", %{routes: routes} do
    assert routes =~ "/admin/systeminfo"
  end
end

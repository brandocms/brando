defmodule Brando.TestRouter do
  use Phoenix.Router
  alias Brando.Plug.Authenticate
  import Brando.Routes.Admin.Users
  import Brando.Routes.Admin.News
  import Brando.Routes.Admin.Images
  import Brando.Routes.Admin.Villain

  pipeline :admin do
    plug :accepts, ~w(html json)
    plug :fetch_session
    plug :fetch_flash
    plug :put_layout, {Brando.Admin.LayoutView, "admin.html"}
    plug Authenticate, login_url: "/login"
  end

  pipeline :browser do
    plug :accepts, ~w(html)
    plug :fetch_session
    plug :fetch_flash
  end

  pipeline :api do
    plug :accepts, ~w(json)
  end

  socket "/ws", Brando do
    channel "admin:*", Brando.AdminChannel
  end

  scope "/admin", as: :admin do
    pipe_through :admin
    user_routes "/brukere", Brando.Admin.UserController,
                               private: %{model: Brando.User}
    user_routes "/brukere2", private: %{model: Brando.User}
    user_routes "/brukere3"
    post_routes "/nyheter"
    post_routes "/nyheter2", [model: Brando.User]
    post_routes "/nyheter3", Brando.Admin.PostController,
                                [model: Brando.User]
    image_routes "/bilder"
    image_routes "/bilder2", [image_model: Brando.Image,
                                 series_model: Brando.ImageSeries,
                                 category_model: Brando.ImageCategory]
    scope "villain" do
      villain_routes Brando.Admin.PostController
    end

    scope "villain2" do
      villain_routes "2", Brando.Admin.PostController
    end

    get "/", Brando.Admin.DashboardController, :dashboard
  end

  scope "/" do
    pipe_through :browser
    get "/login", Brando.AuthController, :login,
      private: %{model: Brando.User,
                 layout: {Brando.Auth.LayoutView, "auth.html"}}
    post "/login", Brando.AuthController, :login,
      private: %{model: Brando.User,
                 layout: {Brando.Auth.LayoutView, "auth.html"}}
    get "/logout", Brando.AuthController, :logout,
      private: %{model: Brando.User,
                 layout: {Brando.Auth.LayoutView, "auth.html"}}
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
    assert routes =~ "/admin/brukere/ny"
    assert routes =~ "/admin/brukere/:id/endre"
  end

  test "news_resources", %{routes: routes} do
    assert routes =~ "/admin/nyheter/ny"
    assert routes =~ "/admin/nyheter/:id/endre"
  end

  test "image_routes", %{routes: routes} do
    assert routes =~ "/admin/bilder/kategorier"
    assert routes =~ "/admin/bilder/kategorier/:id/endre"
  end

  test "villain_routes", %{routes: routes} do
    assert routes =~ "/admin/villain/villain/last-opp"
    assert routes =~ "/admin/villain/villain/bla"
    assert routes =~ "/admin/villain/villain/bildedata"

    assert routes =~ "/admin/villain2/2/villain/last-opp"
    assert routes =~ "/admin/villain2/2/villain/bla"
    assert routes =~ "/admin/villain2/2/villain/bildedata"
  end

end
defmodule <%= application_name %>.AuthController do
  use Brando.Auth.AuthController,
    model: <%= application_name %>.Users.Model.User,
    layout: {<%= application_name %>.Auth.LayoutView, "auth.html"}
end
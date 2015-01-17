defmodule <%= application_name %>.Users.Admin.UserController do
  use Brando.Users.Admin.UserController,
    layout: {<%= application_name %>.Admin.LayoutView, "admin.html"},
    model: <%= application_name %>.Users.Model.User
end
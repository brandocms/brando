defmodule <%= application_name %>.Admin.DashboardController do
  use Brando.Dashboard.Admin.DashboardController,
    layout: {<%= application_name %>.Admin.LayoutView, "admin.html"}
end

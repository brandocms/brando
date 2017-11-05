defmodule <%= application_module %>.ErrorView do
  use <%= application_module %>, :view

  def render("404.html", assigns) do
    render "404_page.html", assigns
  end

  def render("500.html", assigns) do
    render "500_page.html", assigns
  end

  # In case no render clause matches or no
  # template is found, let's render it as 500
  def template_not_found(_template, assigns) do
    render "500.html", assigns
  end
end

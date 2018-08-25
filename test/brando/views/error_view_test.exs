defmodule Brando.ErrorViewTest do
  use Brando.ConnCase, async: true
  import Phoenix.View

  test "renders 404.html" do
    result = render_to_string(Brando.ErrorView, "404.html", conn: Brando.endpoint())
    assert result =~ "Page not found"
    assert result =~ "404"
  end

  test "renders 400.html" do
    result = render_to_string(Brando.ErrorView, "400.html", conn: Brando.endpoint())
    assert result =~ "Bad request"
    assert result =~ "400"
  end

  test "render 500.html" do
    result = render_to_string(Brando.ErrorView, "500.html", conn: Brando.endpoint())
    assert result =~ "Application error"
    assert result =~ "500"
  end

  # test "render 504.html" do
  #   result = render_to_string(Brando.ErrorView, "504.html", [conn: Brando.endpoint])
  #   assert result =~ "Application error"
  #   assert result =~ "504"
  # end

  test "render any other" do
    result =
      render_to_string(Brando.ErrorView, "505.html",
        conn: Brando.endpoint(),
        reason: %{message: "Hello"}
      )

    assert result =~ "Error"
    assert result =~ "Hello"
  end
end

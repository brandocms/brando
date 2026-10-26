defmodule Brando.ColorTest do
  # Colour fields store only colours: the value is written into style
  # attributes and stylesheets and shown to other admins (audit F01).
  use ExUnit.Case, async: true

  alias Brando.Color
  alias Brando.Content.Palette
  alias Brando.Content.Var
  alias Brando.Images.Image

  @markup ~s(<img src="data:," onerror="document.title=1">)

  test "valid?/1 takes what the picker stores and hand-written CSS colours" do
    for value <- [
          nil,
          "",
          "#fff",
          "#ffff",
          "#1a2b3c",
          "#1A2B3Cff",
          "rgb(10, 20, 30)",
          "rgba(10,20,30,0.5)",
          "rgb(10 20 30 / 50%)",
          "hsl(120deg 50% 50%)",
          "hsla(120, 50%, 50%, .5)",
          "transparent",
          "white",
          "var(--brand)",
          "oklch(70% 0.1 200 / .5)",
          "color-mix(in srgb, var(--brand) 40%, white)"
        ] do
      assert Color.valid?(value), inspect(value)
    end

    for value <- [
          @markup,
          "#12",
          "#1234567",
          "red;background:url(x)",
          "rgb(1,2,3);",
          "url(https://example.com)",
          "rgb(1, url(x), 3)",
          "rgb(1, 2, 3",
          "rgb(1, 2, 3))(",
          " #fff",
          "expression(alert(1))",
          "var(--x);color:red",
          ~s(#fff"><b>),
          123
        ] do
      refute Color.valid?(value), inspect(value)
    end
  end

  test "an image's dominant colour must be a colour" do
    image = %Image{path: "images/a.jpg", width: 1, height: 1}

    assert errors_on(Image.changeset(image, %{dominant_color: @markup}, :system))[:dominant_color]
    refute errors_on(Image.changeset(image, %{dominant_color: "#123456"}, :system))[:dominant_color]
  end

  test "a value stored before validation does not block saving other fields" do
    image = %Image{path: "images/a.jpg", width: 1, height: 1, dominant_color: @markup}

    refute errors_on(Image.changeset(image, %{title: %{"en" => "Renamed"}}, :system))[:dominant_color]
  end

  test "palette colours, a subform, are validated row by row" do
    params = fn hex ->
      %{name: "Site", key: "site", colors: [%{name: "Ink", key: "ink", hex_value: hex}]}
    end

    changeset = Palette.changeset(%Palette{}, params.(@markup), :system)
    refute changeset.valid?
    assert [%{hex_value: ["is not a valid colour"]}] = errors_on(changeset)[:colors]

    changeset = Palette.changeset(%Palette{}, params.("#112233"), :system)
    assert errors_on(changeset)[:colors] in [nil, [%{}]]
  end

  test "a colour var's value must be a colour; other vars are not colours" do
    params = %{type: :color, key: "bg", label: %{"en" => "Background"}, value: @markup}

    assert errors_on(Var.changeset(%Var{}, params, :system))[:value]
    refute errors_on(Var.changeset(%Var{}, %{params | value: "#000"}, :system))[:value]
    refute errors_on(Var.changeset(%Var{}, %{params | type: :string}, :system))[:value]
  end

  test "a palette keeps colours it already stored; a new one must be a colour" do
    palette = %Palette{name: "Site", key: "site", colors: [%Palette.Color{name: "Ink", key: "ink", hex_value: "old"}]}
    row = fn hex -> %{name: "Ink", key: "ink", hex_value: hex} end

    assert errors_on(Palette.changeset(palette, %{colors: [row.("old")]}, :system))[:colors] in [nil, [%{}]]

    errors = errors_on(Palette.changeset(palette, %{colors: [row.("old;x")]}, :system))[:colors]
    assert Enum.any?(errors, &match?(%{hex_value: [_]}, &1))
  end

  test "re-reading a stored var skips the check" do
    params = %{type: :color, key: "bg", label: %{"en" => "Background"}, value: "old;x"}

    assert Var.changeset(%Var{}, params, %{id: 0}, nil, validate_colors: false).valid?
    refute Var.changeset(%Var{}, params, %{id: 0}).valid?
  end

  test "a definition snapshot reads a stored colour var that predates the check" do
    var = %Var{type: :color, key: "bg", label: %{"en" => "Background"}, value: "old;x", options: []}

    assert %{"value" => "old;x"} = Brando.Content.Definition.Model.stored_var_record(var)
  end

  test "a var turned into a colour var must already hold a colour" do
    var = %Var{type: :string, key: "bg", label: %{"en" => "Background"}, value: "red;background:url(x)"}

    assert errors_on(Var.changeset(var, %{type: :color}, :system))[:value]
    refute errors_on(Var.changeset(%{var | value: "#000"}, %{type: :color}, :system))[:value]
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end

defmodule Brando.ColorTest.Swatch do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "swatches" do
    field :hex, :string
    field :section_id, :integer
  end

  def changeset(swatch, params), do: cast(swatch, params, [:hex])
end

defmodule Brando.ColorTest.Section do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "sections" do
    field :name, :string
    has_many :swatches, Brando.ColorTest.Swatch
  end

  def changeset(section, params), do: section |> cast(params, [:name]) |> cast_assoc(:swatches)
end

defmodule Brando.ColorTest.Page do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "pages" do
    has_many :sections, Brando.ColorTest.Section
  end

  def changeset(page, params), do: page |> cast(params, []) |> cast_assoc(:sections)
end

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

  test "a palette row kept as stored keeps its colour; a changed or new row must hold a colour" do
    palette = %Palette{name: "Site", key: "site", colors: [%Palette.Color{name: "Ink", key: "ink", hex_value: "old;x"}]}
    row = fn key, hex -> %{name: "Ink", key: key, hex_value: hex} end
    colour_errors = fn rows -> errors_on(Palette.changeset(palette, %{colors: rows}, :system))[:colors] || [] end

    refute Enum.any?(colour_errors.([row.("ink", "old;x")]), &match?(%{hex_value: _}, &1))
    # The stored value copied to another row, or kept in an edited row
    assert Enum.any?(colour_errors.([row.("ink", "old;x"), row.("ink2", "old;x")]), &match?(%{hex_value: _}, &1))
    assert Enum.any?(colour_errors.([%{row.("ink", "old;x") | name: "Renamed"}]), &match?(%{hex_value: _}, &1))
  end

  test "a has_many row kept as stored still has its own subform rows checked" do
    alias Brando.ColorTest.{Page, Section, Swatch}

    page = %Page{id: 1, sections: [%Section{id: 1, name: "A", swatches: [%Swatch{id: 1, hex: "old;x"}]}]}
    fields = [{:sections, [{:swatches, [:hex]}]}]
    swatch = fn hex -> %{"id" => 1, "name" => "A", "swatches" => [%{"id" => 1, "hex" => hex}]} end

    refute Color.validate(Page.changeset(page, %{"sections" => [swatch.("#fff;y")]}), fields).valid?
    assert Color.validate(Page.changeset(page, %{"sections" => [swatch.("#fff")]}), fields).valid?
    assert Color.validate(Page.changeset(page, %{"sections" => [swatch.("old;x")]}), fields).valid?
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

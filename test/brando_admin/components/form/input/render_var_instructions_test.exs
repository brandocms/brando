defmodule BrandoAdmin.Components.Form.Input.RenderVarInstructionsTest do
  # A var's instructions are a language map, as its label is: the editor
  # reads them in their admin language, else the default one
  # (brandocms/brando#3541).
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 2]
  require Phoenix.LiveViewTest

  alias Brando.Content.Var
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias Ecto.Changeset

  setup do
    previous = Gettext.get_locale(Brando.Gettext)
    on_exit(fn -> Gettext.put_locale(Brando.Gettext, previous) end)
  end

  defp render(instructions, opts \\ []) do
    var = %Var{type: :string, key: "title", label: %{"en" => "Title"}, instructions: instructions, value: "x"}
    form = to_form(Changeset.change(var), as: "var")
    Phoenix.LiveViewTest.render_component(RenderVar, [id: "title-var", var: form, edit: false] ++ opts)
  end

  defp shown(html) do
    html |> LazyHTML.from_fragment() |> LazyHTML.query(".help-text span") |> LazyHTML.text() |> String.trim()
  end

  test "an editor reads the instructions in their admin language" do
    instructions = %{"en" => "Keep it short", "no" => "Hold den kort"}

    Gettext.put_locale(Brando.Gettext, "no")
    assert shown(render(instructions)) == "Hold den kort"

    Gettext.put_locale(Brando.Gettext, "en")
    assert shown(render(instructions)) == "Keep it short"
  end

  test "a language without them falls back to the default language" do
    Gettext.put_locale(Brando.Gettext, "no")
    assert shown(render(%{"en" => "Keep it short"})) == "Keep it short"
  end

  test "plain instructions read as they are" do
    assert shown(render("Keep it short")) == "Keep it short"
  end

  test "the module editor edits each language" do
    var = %Var{type: :string, key: "title", label: %{"en" => "Title"}, instructions: %{"en" => "Short", "no" => "Kort"}}
    form = to_form(Changeset.change(var), as: "var")
    html = Phoenix.LiveViewTest.render_component(RenderVar, id: "title-var", var: form, edit: true)
    document = LazyHTML.from_fragment(html)

    values =
      document
      |> LazyHTML.query(~s([name^="var[instructions]"]))
      |> Enum.map(&{&1 |> LazyHTML.attribute("name") |> hd(), &1 |> LazyHTML.attribute("value") |> hd()})

    assert {"var[instructions][en]", "Short"} in values
    assert {"var[instructions][no]", "Kort"} in values
  end
end

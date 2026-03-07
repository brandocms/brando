defmodule BrandoAdmin.Components.Form.Fieldset.FieldTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Blueprint.Forms.Input, as: BlueprintInput
  alias BrandoAdmin.Components.Form.Fieldset.Field

  defmodule TestEntry do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :type_enum, Ecto.Enum, values: [:full_case, :external_link]
      field :type_string, :string
      field :external_link, :string
    end

    def changeset(entry, attrs) do
      cast(entry, attrs, [:type_enum, :type_string, :external_link])
    end
  end

  test "hides when tuple condition matches atom form value against string expected value" do
    form =
      %TestEntry{type_enum: :full_case}
      |> TestEntry.changeset(%{})
      |> to_form(as: :entry)

    html = render_field(form, {:type_enum, "full_case"})

    assert String.trim(html) == ""
  end

  test "hides when tuple condition matches string form value against atom expected value" do
    form =
      %TestEntry{}
      |> TestEntry.changeset(%{"type_string" => "full_case"})
      |> to_form(as: :entry)

    html = render_field(form, {:type_string, :full_case})

    assert String.trim(html) == ""
  end

  test "renders when tuple condition does not match" do
    form =
      %TestEntry{}
      |> TestEntry.changeset(%{"type_string" => "external_link"})
      |> to_form(as: :entry)

    html = render_field(form, {:type_string, :full_case})

    assert html =~ ~s(name="entry[external_link]")
  end

  test "supports hidden function with form arity" do
    form =
      %TestEntry{}
      |> TestEntry.changeset(%{"type_string" => "full_case"})
      |> to_form(as: :entry)

    html =
      render_field(form, fn form ->
        form[:type_string].value == "full_case"
      end)

    assert String.trim(html) == ""
  end

  defp render_field(form, hidden_rule) do
    render_component(&Field.render/1, %{
      input: %BlueprintInput{name: :external_link, type: :text, opts: [hidden: hidden_rule]},
      form: form,
      parent_uploads: %{},
      current_user: nil,
      relations: [],
      form_cid: nil
    })
  end
end

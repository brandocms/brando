defmodule BrandoAdmin.Components.Form.InputAccessibilityTest do
  @moduledoc """
  Every control the admin renders goes through `Input.input/1`, so the accessible
  state of a field is decided in one place. These pin what it emits — issue #1996.
  """
  use ExUnit.Case, async: false

  import Ecto.Changeset, only: [cast: 3, add_error: 3]
  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Primitives

  defp form(params, errors) do
    %Brando.Pages.Page{}
    |> cast(params, [:title, :meta_description])
    |> then(fn changeset ->
      Enum.reduce(errors, changeset, fn {field, message}, acc -> add_error(acc, field, message) end)
    end)
    # Ecto's FormData only exposes errors once the changeset has an action.
    |> Map.put(:action, :validate)
    |> to_form(as: :page)
  end

  defp render_input(form, field, opts \\ []) do
    render_component(
      &Input.input/1,
      Enum.into(opts, %{
        field: form[field],
        id: nil,
        name: nil,
        type: Keyword.get(opts, :type, :text),
        hidden_input: true
      })
    )
  end

  describe "aria-describedby" do
    test "points at the field's message container" do
      html = render_input(form(%{}, []), :title)

      assert html =~ ~s(aria-describedby="page_title-error")
    end

    test "matches the id `field_base/1` gives that container" do
      form = form(%{"title" => ""}, title: "can't be blank")

      input = render_input(form, :title)

      wrapper =
        render_component(&Primitives.field_base/1, %{
          field: form[:title],
          label: "Title",
          inner_block: []
        })

      assert input =~ ~s(aria-describedby="page_title-error")
      assert wrapper =~ ~s(id="page_title-error")
    end
  end

  describe "aria-invalid" do
    test "is absent on an untouched field, even when the changeset carries an error" do
      # A blank create form has errors on every required field before the user
      # has typed anything. Announcing those would read the whole form as
      # broken on arrival, with no messages to explain it.
      html = render_input(form(%{}, title: "can't be blank"), :title)

      refute html =~ "aria-invalid"
    end

    test "is set once the field has been submitted with an error" do
      html = render_input(form(%{"title" => ""}, title: "can't be blank"), :title)

      assert html =~ ~s(aria-invalid="true")
    end

    test "is absent on a submitted field with no error" do
      html = render_input(form(%{"title" => "Fine"}, []), :title)

      refute html =~ "aria-invalid"
    end
  end

  describe "aria-required" do
    test "is set for an attribute the blueprint declares required" do
      assert :title in Brando.Pages.Page.__required_attrs__()

      assert render_input(form(%{}, []), :title) =~ ~s(aria-required="true")
    end

    test "is absent for an optional attribute" do
      refute :meta_description in Brando.Pages.Page.__required_attrs__()

      refute render_input(form(%{}, []), :meta_description) =~ "aria-required"
    end
  end

  describe "hidden inputs" do
    test "carry no accessible annotation at all" do
      # There is nothing for a user to see or reach, so marking one invalid
      # would announce a field that does not exist for them.
      html = render_input(form(%{"title" => ""}, title: "can't be blank"), :title, type: :hidden)

      refute html =~ "aria-invalid"
      refute html =~ "aria-describedby"
      refute html =~ "aria-required"
    end
  end

  describe "textarea and checkbox" do
    test "a textarea is annotated like any other control" do
      html = render_input(form(%{"title" => ""}, title: "can't be blank"), :title, type: :textarea)

      assert html =~ "<textarea"
      assert html =~ ~s(aria-invalid="true")
      assert html =~ ~s(aria-describedby="page_title-error")
    end

    test "a checkbox is annotated on the visible control, not the hidden partner" do
      html = render_input(form(%{"title" => ""}, title: "can't be blank"), :title, type: :checkbox)

      # The paired hidden input that carries the unchecked value must stay bare.
      [hidden, visible] = String.split(html, "<input", trim: true)

      refute hidden =~ "aria-invalid"
      assert visible =~ ~s(aria-invalid="true")
    end
  end
end

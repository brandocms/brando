defmodule BrandoAdmin.Components.Form.ErrorDisplayTest do
  @moduledoc """
  Asset fields are two things in a form: the association, and the `<field>_id`
  column that actually carries a value. Errors land on the id; `used_input?` is
  only ever true for the id. Getting either half wrong is invisible — the label
  reddens with nothing to explain it, or the message never appears at all — so
  both halves are pinned here.
  """
  use ExUnit.Case, async: false

  import Ecto.Changeset, only: [cast: 3, add_error: 3, add_error: 4]
  import ExUnit.CaptureLog, only: [with_log: 1]
  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Primitives

  # A form the user has not interacted with: no params, so used_input? is false
  # for every field.
  defp untouched_form(errors) do
    %Brando.Pages.Page{}
    |> cast(%{}, [:title])
    |> apply_errors(errors)
    |> to_form(as: :page)
  end

  # A submitted form: the id is present in params, which is what makes
  # used_input? true for it.
  defp submitted_form(errors) do
    %Brando.Pages.Page{}
    |> cast(%{"meta_image_id" => nil, "title" => ""}, [:title, :meta_image_id])
    |> apply_errors(errors)
    |> to_form(as: :page)
  end

  defp apply_errors(changeset, errors) do
    errors
    |> Enum.reduce(changeset, fn
      {field, message, opts}, acc -> add_error(acc, field, message, opts)
      {field, message}, acc -> add_error(acc, field, message)
    end)
    # Ecto's FormData only exposes errors once the changeset has an action, so
    # without this the form reports no errors at all and every assertion here
    # would pass for the wrong reason.
    |> Map.put(:action, :validate)
  end

  defp error_tag(form, opts \\ []) do
    render_component(&Primitives.error_tag/1, %{
      field: form[:meta_image],
      relation: Keyword.get(opts, :relation, true),
      id_prefix: "",
      uid: nil
    })
  end

  describe "error_tag/1 for asset fields" do
    test "renders an error stored on the _id column" do
      html = error_tag(submitted_form([{:meta_image_id, "can't be blank"}]))

      assert html =~ "can&#39;t be blank"
    end

    test "stays silent while the field is untouched" do
      html = error_tag(untouched_form([{:meta_image_id, "can't be blank"}]))

      # The `role="alert"` container is always rendered — a live region has to be
      # in the accessibility tree before content lands in it — so what proves
      # silence is that it holds no message, not that it is absent.
      refute html =~ ~s(class="field-error")
      refute html =~ "can&#39;t be blank"
    end

    test "keeps the announcement region in the DOM even with nothing to say" do
      html = error_tag(untouched_form([]))

      assert html =~ ~s(role="alert")
      assert html =~ ~s(id="page_meta_image_id-error")
    end

    test "interpolates a group constraint's fields as their form labels" do
      {html, log} =
        with_log(fn ->
          error_tag(
            submitted_form([
              {:meta_image_id, "requires one of: %{fields}",
               [validation: :one_of, one_of: [:meta_image, :title], fields: "meta_image, title"]}
            ])
          )
        end)

      # The atoms in `fields` are the fallback; the form knows the blueprint and
      # replaces them with the labels the editor sees on those inputs.
      assert log =~ "Could not get field :meta_image from form :default"
      assert html =~ "requires one of:"
      refute html =~ "meta_image, title"
    end
  end

  describe "error_tag/1 label lookup fallback" do
    # label_group_fields/2 reaches for schema.__form__() to turn field atoms into
    # labels. A nested form or an embed is not necessarily a Blueprint, so this
    # is the one path in the change that can meet a struct it did not expect.
    defmodule PlainSchema do
      use Ecto.Schema

      embedded_schema do
        field :meta_image_id, :integer
        field :title, :string
      end
    end

    test "falls back to field names when the struct is not a Blueprint" do
      form =
        %PlainSchema{}
        |> cast(%{"meta_image_id" => nil}, [:meta_image_id])
        |> add_error(:meta_image_id, "requires one of: %{fields}",
          validation: :one_of,
          one_of: [:meta_image, :title],
          fields: "meta_image, title"
        )
        |> Map.put(:action, :validate)
        |> to_form(as: :plain)

      html =
        render_component(&Primitives.error_tag/1, %{
          field: form[:meta_image],
          relation: true,
          id_prefix: "",
          uid: nil
        })

      # Degrades to the atoms rather than raising out of the render.
      assert html =~ "meta_image, title"
    end
  end

  describe "group_constraint_items/3" do
    defp grouped(errors) do
      changeset = untouched_form(errors).source
      Form.group_constraint_items(changeset, Brando.Pages.Page.__form__(), Brando.Pages.Page)
    end

    test "collapses a one_of set into a single entry" do
      {{items, consumed}, log} =
        with_log(fn ->
          grouped([
            {:meta_image_id, "requires one of: %{fields}", [validation: :one_of, one_of: [:meta_image, :title]]},
            {:title, "requires one of: %{fields}", [validation: :one_of, one_of: [:meta_image, :title]]}
          ])
        end)

      assert log =~ "Could not get field :meta_image from form :default"
      assert length(items) == 1
      assert hd(items) =~ ~r/ or /

      # Both fields are consumed, so neither is also listed on its own — the
      # asset by its _id column, the attribute by its own name.
      assert :meta_image_id in consumed
      assert :title in consumed
    end

    test "collapses exactly_one_of the same way" do
      {{items, _consumed}, log} =
        with_log(fn ->
          grouped([
            {:meta_image_id, "requires exactly one of: %{fields}",
             [validation: :exactly_one_of, exactly_one_of: [:meta_image, :title]]}
          ])
        end)

      assert log =~ "Could not get field :meta_image from form :default"
      assert length(items) == 1
    end

    test "leaves ordinary errors alone" do
      assert {[], []} = grouped([{:title, "can't be blank"}])
    end

    test "does not repeat a set that several fields report" do
      {{items, _consumed}, log} =
        with_log(fn ->
          grouped([
            {:meta_image_id, "m", [one_of: [:meta_image, :title]]},
            {:title, "m", [one_of: [:meta_image, :title]]},
            {:meta_image, "m", [one_of: [:meta_image, :title]]}
          ])
        end)

      assert log =~ "Could not get field :meta_image from form :default"
      assert length(items) == 1
    end
  end

  describe "field_base/1 label state" do
    defp field_base(form) do
      render_component(&Primitives.field_base/1, %{
        field: form[:meta_image],
        relation: true,
        label: "META image",
        instructions: nil,
        inner_block: []
      })
    end

    test "flags the label once the field has been used" do
      html = field_base(submitted_form([{:meta_image_id, "can't be blank"}]))

      assert html =~ ~r/class="[^"]*control-label[^"]*failed/
    end

    test "leaves the label clean on an untouched form" do
      # Reading form.errors directly used to redden asset labels the moment a
      # blank create form rendered, with no message to explain them.
      html = field_base(untouched_form([{:meta_image_id, "can't be blank"}]))

      refute html =~ ~r/class="[^"]*control-label[^"]*failed/
    end
  end
end

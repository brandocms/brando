defmodule BrandoAdmin.Components.Form.SubformControlsTest do
  # A many-subform reorders its rows through the relation's `sort_param` and
  # removes them through its `drop_param`. Without the option the cast drops
  # the change without a word, so the subform draws no control for it, and
  # the form warns when it compiles.
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO, only: [capture_io: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.SubformControlsTest.Part
  alias Brando.SubformControlsTest.Row
  alias BrandoAdmin.Components.Form.Subform
  alias Ecto.Changeset

  # `relations` is the blueprint's relations block, `style` its subforms'
  defp compile_holder(relations, style \\ :inline) do
    module = Module.concat(__MODULE__, "Holder#{System.unique_integer([:positive])}")

    stderr =
      capture_io(:stderr, fn ->
        Code.compile_quoted(
          quote do
            defmodule unquote(module) do
              use Brando.Blueprint,
                application: "Brando",
                domain: "SubformControlsTest",
                schema: "Holder",
                singular: "holder",
                plural: "holders",
                gettext_module: Brando.Gettext

              identifier false
              persist_identifier false

              attributes do
                attribute :title, :string
              end

              unquote(relations)

              forms do
                form do
                  tab "Content" do
                    fieldset do
                      inputs_for :rows do
                        cardinality :many
                        style unquote(style)
                        default %{}
                        input :title, :text
                      end

                      inputs_for :parts do
                        cardinality :many
                        style unquote(style)
                        default %{}
                        input :title, :text
                      end
                    end
                  end
                end
              end
            end
          end,
          "test/support/holder.ex"
        )
      end)

    {module, stderr}
  end

  defp bare do
    quote do
      relations do
        relation :rows, :embeds_many, module: Brando.SubformControlsTest.Row, on_replace: :delete

        relation :parts, :has_many,
          module: Brando.SubformControlsTest.Part,
          foreign_key: :holder_id,
          cast: true,
          on_replace: :delete
      end
    end
  end

  defp complete do
    quote do
      relations do
        relation :rows, :embeds_many,
          module: Brando.SubformControlsTest.Row,
          on_replace: :delete,
          sort_param: :sort_rows_ids,
          drop_param: :drop_rows_ids

        relation :parts, :has_many,
          module: Brando.SubformControlsTest.Part,
          foreign_key: :holder_id,
          cast: true,
          on_replace: :delete,
          sort_param: :sort_parts_ids,
          drop_param: :drop_parts_ids
      end
    end
  end

  defp sort_only do
    quote do
      relations do
        relation :rows, :embeds_many,
          module: Brando.SubformControlsTest.Row,
          on_replace: :delete,
          sort_param: :sort_rows_ids

        relation :parts, :has_many,
          module: Brando.SubformControlsTest.Part,
          foreign_key: :holder_id,
          cast: true,
          on_replace: :delete,
          drop_param: :drop_parts_ids
      end
    end
  end

  defp entry(module) do
    struct(module,
      id: 1,
      rows: [%Row{id: "a", title: "A"}, %Row{id: "b", title: "B"}],
      parts: [%Part{id: 1, title: "A", sequence: 0, holder_id: 1}, %Part{id: 2, title: "B", sequence: 1, holder_id: 1}]
    )
  end

  # The params the form sends after the editor moved the second row up and
  # removed the first
  defp reordered_and_removed(field) do
    [a, b] = if field == :rows, do: ["a", "b"], else: ["1", "2"]

    %{
      "#{field}" => %{"0" => %{"id" => a, "title" => "A"}, "1" => %{"id" => b, "title" => "B"}},
      "sort_#{field}_ids" => ["1", "0"],
      "drop_#{field}_ids" => ["0"]
    }
  end

  defp titles(changeset, field), do: changeset |> Changeset.apply_changes() |> Map.fetch!(field) |> Enum.map(& &1.title)

  describe "the cast" do
    test "without the options, a reorder and a removal are cast away" do
      {module, _stderr} = compile_holder(bare())

      for field <- [:rows, :parts] do
        changeset = module.changeset(entry(module), reordered_and_removed(field))

        assert titles(changeset, field) == ["A", "B"], "#{field}"
      end
    end

    test "with them, both are kept" do
      {module, _stderr} = compile_holder(complete())

      for field <- [:rows, :parts] do
        changeset = module.changeset(entry(module), reordered_and_removed(field))

        assert titles(changeset, field) == ["B"], "#{field}"
      end
    end
  end

  describe "the compile warning" do
    test "names the blueprint, the relation, the missing options and the line to add" do
      {module, stderr} = compile_holder(bare())

      assert stderr =~ inspect(module)
      assert stderr =~ "relation :rows"
      assert stderr =~ "relation :parts"
      assert stderr =~ "sort_param: :sort_rows_ids, drop_param: :drop_rows_ids"
      assert stderr =~ "sort_param: :sort_parts_ids, drop_param: :drop_parts_ids"
      assert stderr =~ "test/support/holder.ex"
    end

    test "names only the option that is missing" do
      {_module, stderr} = compile_holder(sort_only())

      assert stderr =~ "drop_param: :drop_rows_ids"
      refute stderr =~ "sort_param: :sort_rows_ids"
      assert stderr =~ "sort_param: :sort_parts_ids"
      refute stderr =~ "drop_param: :drop_parts_ids"
    end

    test "is not emitted for a complete relation" do
      {_module, stderr} = compile_holder(complete())
      refute stderr =~ "sort_param"
      refute stderr =~ "drop_param"
    end
  end

  defp render_subform(module, name, style) do
    form = module |> entry() |> Changeset.change() |> Phoenix.Component.to_form()
    subform = Brando.Blueprint.Forms.get_field(name, module.__form__())

    Subform
    |> render_component(
      id: "subform-#{name}-#{style}",
      field: form[name],
      subform: subform,
      label: "Rows",
      instructions: nil,
      placeholder: nil,
      current_user: nil,
      parent_form_id: "holder_form"
    )
    |> Floki.parse_fragment!()
  end

  defp has?(html, selector), do: Floki.find(html, selector) != []

  describe "the rendered subform" do
    for style <- [:inline, :regular] do
      @style style

      test "#{style}: no handle and no remove button without the options" do
        {module, _stderr} = compile_holder(bare(), @style)

        for name <- [:rows, :parts] do
          html = render_subform(module, name, @style)
          refute has?(html, "button.subform-handle"), "#{name}"
          refute has?(html, "button.subform-delete"), "#{name}"
          refute has?(html, ~s([phx-hook="Brando.SortableEmbeds"])), "#{name}"
          # Rows can still be added
          assert has?(html, "button.add-entry-button"), "#{name}"
        end
      end

      test "#{style}: handle and remove button with them" do
        {module, _stderr} = compile_holder(complete(), @style)

        for name <- [:rows, :parts] do
          html = render_subform(module, name, @style)
          assert has?(html, "button.subform-handle"), "#{name}"
          assert has?(html, "button.subform-delete"), "#{name}"
          assert has?(html, ~s([phx-hook="Brando.SortableEmbeds"])), "#{name}"
        end
      end
    end

    test "each control follows its own option" do
      {module, _stderr} = compile_holder(sort_only())

      rows = render_subform(module, :rows, :inline)
      assert has?(rows, "button.subform-handle")
      refute has?(rows, "button.subform-delete")

      parts = render_subform(module, :parts, :inline)
      refute has?(parts, "button.subform-handle")
      assert has?(parts, "button.subform-delete")
    end
  end
end

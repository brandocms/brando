defmodule BrandoAdmin.Components.Form.Block.DatasourcePickerTest do
  use ExUnit.Case, async: true

  alias Brando.Content.Identifier
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Block.Events
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Ecto.Changeset
  alias Phoenix.Component

  defmodule Datasources do
    use Brando.Blueprint,
      application: "BrandoIntegration",
      domain: "Tests",
      schema: "PickerDatasource",
      singular: "picker_datasource",
      plural: "picker_datasources",
      gettext_module: Brando.Gettext

    datasources do
      datasource :get_only do
        type :single
        get fn identifier -> {:ok, identifier} end
      end

      datasource :failed_choices do
        type :single
        list fn _, _, _ -> {:error, :unavailable} end
        get fn identifier -> {:ok, identifier} end
      end
    end
  end

  test "loading options for a get-only single datasource returns no choices" do
    socket = socket_for(:root, :single)

    assert {:halt, socket} = Events.handle_block_event("assign_available_identifiers", %{}, socket)
    assert socket.assigns.available_identifiers == []
    assert Brando.Datasource.get_single(Datasources, :get_only, %Identifier{id: 1}) == {:ok, %Identifier{id: 1}}
  end

  test "errors from an existing list callback are preserved" do
    assert Brando.Datasource.list_results(Datasources, :failed_choices, [], "en", :single) ==
             {:error, :unavailable}
  end

  for belongs_to <- [:root, {:child, "parent"}], type <- [:single, :selection] do
    test "clearing a just-synchronized #{type} selection emits a saveable op for #{inspect(belongs_to)}" do
      belongs_to = unquote(Macro.escape(belongs_to))
      socket = socket_for(belongs_to, unquote(type))
      uid = socket.assigns.uid
      original_form = socket.assigns.form

      # A remote pick replaces an empty form. Clicking that same entry to
      # clear it immediately is an intentional edit, not a stale form echo.
      selected =
        original_form.source
        |> Block.get_block_changeset(belongs_to)
        |> Changeset.put_assoc(:block_identifiers, [%{identifier_id: 1, sequence: 0}])

      remote_changeset = Block.update_block_changeset(original_form.source, selected, belongs_to)
      remote_form = form_for(remote_changeset, belongs_to)

      assert {:ok, socket} = Block.update(%{event: "replace_form", form: remote_form}, socket)
      assert {:halt, socket} = Events.handle_block_event("select_identifier", %{"id" => "1"}, socket)

      assert socket.assigns.form.source
             |> Block.get_block_changeset(belongs_to)
             |> Changeset.get_field(:block_identifiers) == []

      assert_receive {:phoenix, :send_update, {_, %{event: "block_op", op: op}}}

      # Save and the edit session both use this reducer, rather than the
      # component's form. Its materialized selection must also be empty.
      root = root_with(remote_changeset, belongs_to)
      ops = Ops.from_entry_blocks([Changeset.apply_changes(root)])
      assert {:ok, ops} = Ops.apply_op(ops, op)
      assert {:ok, params} = Ops.materialize_root(ops, root_uid(belongs_to))
      assert get_in(params, selection_path(belongs_to)) == []
      assert elem(op, 1) == uid
    end
  end

  defp socket_for(belongs_to, type) do
    block =
      %Brando.Content.Block{
        id: 1,
        uid: "picked-block",
        type: :module,
        vars: [],
        refs: [],
        children: [],
        block_identifiers: [],
        table_rows: []
      }
      |> Ecto.put_meta(state: :loaded)

    changeset =
      if belongs_to == :root,
        do: Changeset.change(%Brando.Pages.Page.Blocks{id: 1, block_id: block.id, block: block}),
        else: Changeset.change(block)

    Component.assign(%Phoenix.LiveView.Socket{},
      id: "picked-block",
      uid: block.uid,
      form: form_for(changeset, belongs_to),
      belongs_to: belongs_to,
      current_user_id: 1,
      original_block_identifiers: [],
      available_identifiers: [%Identifier{id: 1}],
      is_datasource?: true,
      module_datasource_type: type,
      module_datasource_module: Datasources,
      module_datasource_query: :get_only,
      entry: %{language: "en"},
      live_preview_active?: false,
      form_id: "page_form",
      block_field: "blocks"
    )
  end

  defp form_for(changeset, :root),
    do: Component.to_form(changeset, as: "entry_block", id: "entry_block_form-picked-block")

  defp form_for(changeset, _child),
    do: Component.to_form(changeset, as: "child_block", id: "child_block_form-picked-block")

  defp root_with(changeset, :root), do: changeset

  defp root_with(changeset, _child) do
    Changeset.change(%Brando.Pages.Page.Blocks{
      id: 2,
      block: %Brando.Content.Block{
        id: 2,
        uid: "parent",
        type: :container,
        children: [Changeset.apply_changes(changeset)]
      }
    })
  end

  defp root_uid(:root), do: "picked-block"
  defp root_uid(_child), do: "parent"

  defp selection_path(:root), do: ["block", "block_identifiers"]
  defp selection_path(_child), do: ["block", "children", Access.at(0), "block_identifiers"]
end

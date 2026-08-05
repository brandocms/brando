defmodule BrandoAdmin.Components.Form.Block.ChildDiffTest do
  # Regression coverage for B2 — a persisted CHILD block retained only its most
  # recently edited field.
  #
  # The child `validate_block` clause rebases on `apply_changes(changeset)` (the
  # in-memory state), so each emitted diff is a *delta since the last validate*,
  # not a cumulative diff vs. the DB. `{:update, …}` then replaced the stored
  # diff wholesale, so edit `description` then `anchor` and the description was
  # gone by save time.
  #
  # Roots are unaffected: they rebase on `changeset.data`, so their diffs are
  # already cumulative vs. the DB and replacing is the correct semantic there.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 2]

  alias Brando.Factory
  alias BrandoAdmin.Components.Form.Block.Events
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)

    entry_block =
      %Brando.Pages.Page.Blocks{}
      |> Changeset.change(%{entry_id: page.id, sequence: 0})
      |> Changeset.put_assoc(:block, %{
        uid: "containerX",
        type: :container,
        active: true,
        source: "Elixir.Brando.Pages.Page.Blocks",
        creator_id: user.id,
        sequence: 0,
        children: [
          %{
            uid: "childY",
            type: :module,
            active: true,
            description: "before",
            source: "Elixir.Brando.Pages.Page.Blocks",
            creator_id: user.id,
            sequence: 0
          }
        ]
      })
      |> Brando.Repo.insert!()

    entry_block =
      Brando.Repo.preload(entry_block, [
        :entry,
        block: [children: [:vars, :refs, :table_rows, :block_identifiers]]
      ])

    [child] = entry_block.block.children

    {:ok, user: user, entry_block: entry_block, child: child}
  end

  defp socket_for(changeset, entry, user) do
    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(:form, to_form(changeset, as: "child_block", id: "child_block_form-childY"))
    |> Phoenix.Component.assign(:uid, "childY")
    |> Phoenix.Component.assign(:current_user_id, user.id)
    |> Phoenix.Component.assign(:entry, entry)
    |> Phoenix.Component.assign(:has_vars?, false)
    |> Phoenix.Component.assign(:has_table_rows?, false)
    |> Phoenix.Component.assign(:live_preview_active?, false)
    |> Phoenix.Component.assign(:original_block_identifiers, [])
    |> Phoenix.Component.assign(:form_id, "page_form")
    |> Phoenix.Component.assign(:block_field, "blocks")
    |> Phoenix.Component.assign(:belongs_to, {:child, "containerX"})
  end

  defp validate(socket, target, params) do
    payload = %{
      "_target" => ["child_block", target],
      "child_block" => Map.merge(%{"uid" => "childY", "type" => "module"}, params)
    }

    assert {:halt, socket} = Events.handle_block_event("validate_block", payload, socket)
    {socket, captured_op()}
  end

  # `Block.assign_block_form/2` emits the op through `send_update`, which outside
  # a LiveView process is just a message to self() — so the real op is capturable.
  defp captured_op do
    receive do
      {:phoenix, :send_update, {_ref, %{op: op}}} -> op
    after
      0 -> flunk("no block op was emitted")
    end
  end

  test "two sequential edits on a persisted child both survive", ctx do
    %{entry_block: entry_block, child: child, user: user} = ctx

    socket = socket_for(Changeset.change(child), entry_block.entry, user)

    {socket, op1} = validate(socket, "description", %{"description" => "abc"})
    assert {:update, "childY", %{"description" => "abc"}} = op1

    {_socket, op2} = validate(socket, "anchor", %{"description" => "abc", "anchor" => "z"})
    assert {:update, "childY", _} = op2

    # the op store is what save materializes from — both edits must be in it
    ops =
      Ops.new([])
      |> apply_op!({:insert, "containerX", 0, %{"block" => %{"uid" => "containerX"}}})
      |> apply_op!({:insert_child, "containerX", "childY", 0, %{"uid" => "childY"}})
      |> apply_op!(op1)
      |> apply_op!(op2)

    diff = ops.diffs["childY"]

    assert diff["description"] == "abc", "the first edit must not be discarded by the second"
    assert diff["anchor"] == "z"
  end

  test "a later edit still overwrites the same field", ctx do
    %{entry_block: entry_block, child: child, user: user} = ctx

    socket = socket_for(Changeset.change(child), entry_block.entry, user)

    {socket, op1} = validate(socket, "description", %{"description" => "abc"})
    {_socket, op2} = validate(socket, "description", %{"description" => "xyz"})

    ops =
      Ops.new([])
      |> apply_op!({:insert, "containerX", 0, %{"block" => %{"uid" => "containerX"}}})
      |> apply_op!({:insert_child, "containerX", "childY", 0, %{"uid" => "childY"}})
      |> apply_op!(op1)
      |> apply_op!(op2)

    assert ops.diffs["childY"]["description"] == "xyz"
  end

  test "reverting a child field back to its DB value is not resurrected", ctx do
    %{entry_block: entry_block, child: child, user: user} = ctx

    socket = socket_for(Changeset.change(child), entry_block.entry, user)

    {socket, op1} = validate(socket, "description", %{"description" => "abc"})
    {_socket, op2} = validate(socket, "description", %{"description" => "before"})

    ops =
      Ops.new([])
      |> apply_op!({:insert, "containerX", 0, %{"block" => %{"uid" => "containerX"}}})
      |> apply_op!({:insert_child, "containerX", "childY", 0, %{"uid" => "childY"}})
      |> apply_op!(op1)
      |> apply_op!(op2)

    assert ops.diffs["childY"]["description"] == "before",
           "a merge must not resurrect the superseded value"
  end

  test "two edits on a persisted child both survive a real save", ctx do
    %{entry_block: entry_block, child: child, user: user} = ctx

    socket = socket_for(Changeset.change(child), entry_block.entry, user)
    {socket, op1} = validate(socket, "description", %{"description" => "abc"})
    {_socket, op2} = validate(socket, "anchor", %{"description" => "abc", "anchor" => "z"})

    entry_blocks = preloaded_entry_blocks(entry_block.entry_id)

    ops =
      entry_blocks
      |> Ops.from_entry_blocks()
      |> apply_op!(op1)
      |> apply_op!(op2)

    assert {:ok, _} = save_from_ops(entry_block.entry, entry_blocks, ops, user)

    [%{block: %{children: [saved]}}] = preloaded_entry_blocks(entry_block.entry_id)

    assert saved.description == "abc", "the first edit must persist"
    assert saved.anchor == "z"
  end

  defp preloaded_entry_blocks(page_id) do
    import Ecto.Query

    Brando.Pages.Page.Blocks
    |> where([eb], eb.entry_id == ^page_id)
    |> order_by([eb], eb.sequence)
    |> Brando.Repo.all()
    |> Brando.Repo.preload(
      block: [
        :vars,
        :refs,
        :table_rows,
        :block_identifiers,
        children: &Brando.Content.Blocks.preload_child_trees/1
      ]
    )
  end

  # the same save path BlockField + the Form run (see blocks_cross_parent_move_test)
  defp save_from_ops(page, entry_blocks, ops, user) do
    by_uid = Map.new(entry_blocks, &{&1.block.uid, &1})

    updated =
      ops.order
      |> Enum.map(fn uid ->
        {:ok, params} = Ops.materialize_root(ops, uid)
        Brando.Pages.Page.Blocks.changeset(by_uid[uid], params, user.id, true)
      end)
      |> Brando.Content.Blocks.reject_deleted(true)
      |> Brando.Content.Blocks.strip_render_artifacts()
      |> Enum.map(&Brando.Utils.set_action/1)

    page
    |> Brando.Repo.preload(:entry_blocks)
    |> Changeset.change()
    |> Changeset.put_assoc(:entry_blocks, updated)
    |> Brando.Repo.update()
  end

  defp apply_op!(state, op) do
    {:ok, state} = Ops.apply_op(state, op)
    state
  end
end

defmodule BrandoAdmin.Components.Form.Block.RecoverBlocksSecurityTest do
  # Coverage for C5 — `recover_blocks` is the one editor path that casts a raw
  # params tree from the browser straight into new DB rows. Everything else the
  # editor sends is a `validate` against a changeset the server already built.
  #
  # Before this, only `entry_id` was forced. `blueprint.ex:318` casts `block_id`
  # (so a payload could attach this entry to another entry's block row) and
  # `@block_attrs` casts `parent_id`, `creator_id` and `source` (cross-entry
  # child injection and creator spoofing). The recovered uid was also read back
  # out of the client's own params rather than from the set the server vetted.
  #
  # These are all "authenticated admin" findings — Brando has no tenant boundary
  # and every admin can already reach every asset through the pickers. What is
  # defended here is ownership and identity, not visibility.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Ecto.Changeset

  @block_module Brando.Pages.Page.Blocks

  setup do
    user = Factory.insert(:random_user)
    attacker = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    other_page = Factory.insert(:page, creator: user)

    {:ok, module} =
      Brando.Content.create_module(
        %{
          name: %{"en" => "Text"},
          namespace: %{"en" => "test"},
          help_text: %{"en" => "help"},
          class: "text",
          code: "<div>{{ title }}</div>",
          refs: [],
          vars: []
        },
        user
      )

    # A block belonging to a different entry — the row a forged payload would
    # try to attach itself to.
    other_entry_block =
      %@block_module{}
      |> Changeset.change(%{entry_id: other_page.id, sequence: 0})
      |> Changeset.put_assoc(:block, %{
        uid: "victimBlock",
        type: :module,
        active: true,
        source: to_string(@block_module),
        creator_id: user.id,
        module_id: module.id,
        sequence: 0
      })
      |> Brando.Repo.insert!()

    {:ok,
     user: user,
     attacker: attacker,
     page: page,
     other_page: other_page,
     module: module,
     other_entry_block: other_entry_block}
  end

  defp socket(user, page, opts \\ []) do
    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(:block_module, @block_module)
    |> Phoenix.Component.assign(:current_user, user)
    |> Phoenix.Component.assign(:entry, page)
    |> Phoenix.Component.assign(:entry_blocks, [])
    |> Phoenix.Component.assign(:seed_forms, Keyword.get(opts, :seed_forms, %{}))
    |> Phoenix.Component.assign(:block_ops, Ops.new(Keyword.get(opts, :order, [])))
    |> Phoenix.Component.assign(:block_field, "blocks")
    |> Phoenix.Component.assign(:form_id, "page_form")
    |> Phoenix.Component.assign(:blocks_changed?, false)
  end

  defp payload(block_params, opts \\ []) do
    %{
      "rootUids" => ["rootA"],
      "currentUids" => [],
      "missingUids" => Keyword.get(opts, :missing_uids, ["rootA"]),
      "childOrder" => Keyword.get(opts, :child_order, %{}),
      "forms" =>
        Map.merge(
          %{
            "entry_block_form-rootA" => %{
              "entry_block" =>
                Map.merge(
                  %{"sequence" => "0", "block" => block_params},
                  Keyword.get(opts, :entry_block, %{})
                )
            }
          },
          Keyword.get(opts, :extra_forms, %{})
        )
    }
  end

  defp base_block(module, user, extra \\ %{}) do
    Map.merge(
      %{
        "uid" => "rootA",
        "type" => "module",
        "active" => "true",
        "description" => "recovered",
        "module_id" => to_string(module.id),
        "creator_id" => to_string(user.id),
        "source" => to_string(@block_module)
      },
      extra
    )
  end

  defp recover(params, socket) do
    BlockField.handle_event("recover_blocks", params, socket)
  end

  defp recovered_cs(socket, uid) do
    socket.assigns.seed_forms |> Map.fetch!(uid) |> Map.fetch!(:source)
  end

  test "a forged block_id cannot attach the entry to another entry's block", ctx do
    %{user: user, page: page, module: module, other_entry_block: other} = ctx

    params =
      payload(base_block(module, user),
        entry_block: %{"block_id" => to_string(other.block_id)}
      )

    assert {:reply, _, socket} = recover(params, socket(user, page))

    entry_block_cs = recovered_cs(socket, "rootA")

    refute Map.has_key?(entry_block_cs.changes, :block_id)
    assert Changeset.get_field(entry_block_cs, :block_id) == nil

    # The block that came back is a brand new one, not the victim row.
    block_cs = Changeset.get_assoc(entry_block_cs, :block)
    assert Changeset.get_field(block_cs, :uid) == "rootA"
    assert block_cs.data.id == nil
  end

  test "creator_id is forced from current_user, not taken from params", ctx do
    %{user: user, attacker: attacker, page: page, module: module} = ctx

    params = payload(base_block(module, user, %{"creator_id" => to_string(attacker.id)}))

    assert {:reply, _, socket} = recover(params, socket(user, page))

    block_cs = socket |> recovered_cs("rootA") |> Changeset.get_assoc(:block)
    assert Changeset.get_field(block_cs, :creator_id) == user.id
  end

  test "a forged parent_id is dropped", ctx do
    %{user: user, page: page, module: module, other_entry_block: other} = ctx

    params = payload(base_block(module, user, %{"parent_id" => to_string(other.block_id)}))

    assert {:reply, _, socket} = recover(params, socket(user, page))

    block_cs = socket |> recovered_cs("rootA") |> Changeset.get_assoc(:block)
    assert Changeset.get_field(block_cs, :parent_id) == nil
  end

  test "source is forced to the field's own block module", ctx do
    %{user: user, page: page, module: module} = ctx

    params = payload(base_block(module, user, %{"source" => "Elixir.Some.Other.Blocks"}))

    assert {:reply, _, socket} = recover(params, socket(user, page))

    block_cs = socket |> recovered_cs("rootA") |> Changeset.get_assoc(:block)
    assert Changeset.get_field(block_cs, :source) == @block_module
  end

  test "the recovered block is keyed by the vetted uid, not the one in the form body", ctx do
    %{user: user, page: page, module: module} = ctx

    # `missingUids` says rootA; the form body claims to be some other block.
    params = payload(base_block(module, user, %{"uid" => "someOtherBlock"}))

    assert {:reply, %{recovered: ["rootA"]}, socket} = recover(params, socket(user, page))

    assert Map.keys(socket.assigns.seed_forms) == ["rootA"]

    block_cs = socket |> recovered_cs("rootA") |> Changeset.get_assoc(:block)
    assert Changeset.get_field(block_cs, :uid) == "rootA"
  end

  test "a uid the server already holds is not recoverable", ctx do
    %{user: user, page: page, module: module} = ctx

    params = payload(base_block(module, user))

    # The block is alive in this process's op store — a replayed or forged
    # payload must not overwrite it.
    assert {:reply, %{recovered: []}, socket} =
             recover(params, socket(user, page, order: ["rootA"]))

    assert socket.assigns.seed_forms == %{}
  end

  test "a uid already seeded is not recoverable", ctx do
    %{user: user, page: page, module: module} = ctx

    params = payload(base_block(module, user))
    socket = socket(user, page, seed_forms: %{"rootA" => :existing_form})

    assert {:reply, %{recovered: []}, socket} = recover(params, socket)
    assert socket.assigns.seed_forms == %{"rootA" => :existing_form}
  end

  test "nested vars are scrubbed of ownership and identity keys", ctx do
    %{user: user, attacker: attacker, page: page, module: module, other_entry_block: other} = ctx

    block_params =
      base_block(module, user, %{
        "vars" => %{
          "0" => %{
            "type" => "string",
            "key" => "title",
            "label" => "Title",
            "value" => "hello",
            "creator_id" => to_string(attacker.id),
            "block_id" => to_string(other.block_id),
            "page_id" => to_string(other.entry_id),
            "id" => "999999"
          }
        }
      })

    assert {:reply, _, socket} = recover(payload(block_params), socket(user, page))

    block_cs = socket |> recovered_cs("rootA") |> Changeset.get_assoc(:block)
    assert [var_cs] = Changeset.get_assoc(block_cs, :vars)

    # The value the user typed survives; the identity the client attached does not.
    assert Changeset.get_field(var_cs, :value) == "hello"
    assert Changeset.get_field(var_cs, :id) == nil
    assert Changeset.get_field(var_cs, :block_id) == nil
    assert Changeset.get_field(var_cs, :page_id) == nil
    refute Changeset.get_field(var_cs, :creator_id) == attacker.id
  end

  test "children smuggled through the root block params are ignored", ctx do
    %{user: user, page: page, module: module} = ctx

    block_params =
      base_block(module, user, %{
        "children" => [
          %{
            "uid" => "smuggled",
            "type" => "module",
            "active" => "true",
            "description" => "not via childOrder",
            "module_id" => to_string(module.id)
          }
        ]
      })

    assert {:reply, _, socket} = recover(payload(block_params), socket(user, page))

    block_cs = socket |> recovered_cs("rootA") |> Changeset.get_assoc(:block)
    assert Changeset.get_assoc(block_cs, :children) == []
  end

  test "children arriving through childOrder are sanitized too", ctx do
    %{user: user, attacker: attacker, page: page, module: module, other_entry_block: other} = ctx

    params =
      payload(base_block(module, user),
        child_order: %{"rootA" => ["childA"]},
        extra_forms: %{
          "child_block_form-childA" => %{
            "child_block" => %{
              "uid" => "childA",
              "type" => "module",
              "active" => "true",
              "description" => "child",
              "module_id" => to_string(module.id),
              "creator_id" => to_string(attacker.id),
              "parent_id" => to_string(other.block_id),
              "source" => "Elixir.Some.Other.Blocks"
            }
          }
        }
      )

    assert {:reply, _, socket} = recover(params, socket(user, page))

    block_cs = socket |> recovered_cs("rootA") |> Changeset.get_assoc(:block)
    assert [child_cs] = Changeset.get_assoc(block_cs, :children)

    assert Changeset.get_field(child_cs, :description) == "child"
    assert Changeset.get_field(child_cs, :creator_id) == user.id
    assert Changeset.get_field(child_cs, :parent_id) == nil
    assert Changeset.get_field(child_cs, :source) == @block_module
  end

  # W3 from the Phase 0 review, deliberately deferred to Phase 1 so the carried
  # surface and the recover path would be whitelisted together.
  #
  # `carried_var/1` round-trips an unsaved var's whole cast surface through
  # hidden inputs, so every attribute in that set is hand-editable before
  # submit. B4 widened `@var_attrs` by six fields and widened that DOM surface
  # with it.
  describe "carried var surface" do
    test "excludes ownership and parentage, keeps values" do
      carried = Brando.Content.Block.carried_var_attrs()

      for owner_attr <- [
            :creator_id,
            :block_id,
            :page_id,
            :module_id,
            :global_set_id,
            :table_template_id
          ] do
        refute owner_attr in carried,
               "#{owner_attr} is server authority and must not be client-editable"
      end

      # A palette or identifier var stores its value in these — dropping them
      # would be silent data loss on the first save, which is the trap the
      # identity-only shortcut falls into.
      for value_attr <- [
            :type,
            :key,
            :value,
            :placement,
            :palette_id,
            :identifier_id,
            :image_id,
            :video_id,
            :gallery_id,
            :file_id,
            :config_target
          ] do
        assert value_attr in carried
      end
    end

    test "carried set is a strict subset of the cast surface" do
      carried = MapSet.new(Brando.Content.Block.carried_var_attrs())
      cast = MapSet.new(Brando.Content.Block.var_attrs())

      # Anything carried but not cast would be a dead input; anything cast is
      # allowed to be absent, but the two must not drift the other way.
      assert MapSet.subset?(carried, cast)
      refute MapSet.equal?(carried, cast)
    end

    test "var_changeset ignores a client-supplied creator_id", %{user: user, attacker: attacker} do
      changeset =
        Brando.Content.Block.var_changeset(
          %Brando.Content.Var{},
          %{"type" => "string", "key" => "title", "creator_id" => to_string(attacker.id)},
          user.id
        )

      assert Changeset.get_field(changeset, :creator_id) == user.id
    end

    test "an existing var keeps its original creator", %{user: user, attacker: attacker} do
      # Not "last editor wins" — forcing on every cast would rewrite authorship
      # whenever someone else edits the block.
      changeset =
        Brando.Content.Block.var_changeset(
          %Brando.Content.Var{id: 1, creator_id: attacker.id},
          %{"value" => "edited", "creator_id" => to_string(attacker.id)},
          user.id
        )

      assert Changeset.get_field(changeset, :creator_id) == attacker.id
      refute Map.has_key?(changeset.changes, :creator_id)
    end
  end
end

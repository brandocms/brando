defmodule BrandoAdmin.Components.Form.Block.RecoverChildrenTest do
  # Regression coverage for C1 — a brand-new unsaved ROOT block came back from
  # recovery with all of its children gone.
  #
  # Two independent halves of the same hole:
  #
  #   1. The JS hook captured every block form (root *and* child) but only ever
  #      forwarded ones matching `entry_block_form-${uid}`, so child params
  #      never reached the server.
  #   2. The server built its base struct with `children: []` and cast through
  #      the 3-arity `changeset/3`, which has no `cast_assoc(:children)` — so
  #      even had the params arrived, they would have been dropped silently.
  #
  # This is the one case default LiveView form recovery structurally cannot
  # reach: the blocks were never persisted, so there is no DB row to rebase a
  # replayed `validate` on.
  #
  # These tests drive the server half — `handle_event("recover_blocks", …)` —
  # with the payload shape the hook now sends, including `childOrder`.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Ecto.Changeset
  alias Phoenix.Component

  @block_module Brando.Pages.Page.Blocks

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)

    {:ok, module} =
      Brando.Content.create_module(
        %{
          name: %{"en" => "Text"},
          namespace: %{"en" => "test"},
          help_text: %{"en" => "help"},
          class: "text",
          code: "<div>{{ title }}</div>",
          refs: [],
          vars: [
            %{
              type: :string,
              label: "Title",
              key: "title",
              value: "Default title",
              placement: :content,
              width: :full
            }
          ]
        },
        user
      )

    {:ok, user: user, page: page, module: module}
  end

  defp socket(user, page) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:block_module, @block_module)
    |> Component.assign(:current_user, user)
    |> Component.assign(:entry, page)
    |> Component.assign(:entry_blocks, [])
    |> Component.assign(:seed_forms, %{})
    |> Component.assign(:block_ops, Ops.new([]))
    |> Component.assign(:block_field, "blocks")
    |> Component.assign(:form_id, "page_form")
    |> Component.assign(:blocks_changed?, false)
  end

  # The params the hook's `formDataToParams` produces for one root block form.
  defp root_form_params(uid, module, user, opts \\ []) do
    %{
      "entry_block" => %{
        "sequence" => "0",
        "block" => %{
          "uid" => uid,
          "type" => "container",
          "active" => "true",
          "description" => Keyword.get(opts, :description, "root description"),
          "module_id" => to_string(module.id),
          "creator_id" => to_string(user.id),
          "source" => to_string(@block_module)
        }
      }
    }
  end

  defp child_form_params(uid, module, user, opts) do
    %{
      "child_block" => %{
        "uid" => uid,
        "type" => "module",
        "active" => "true",
        "description" => Keyword.get(opts, :description, "child description"),
        "module_id" => to_string(module.id),
        "creator_id" => to_string(user.id),
        "source" => to_string(@block_module)
      }
    }
  end

  defp recovered_block(socket, uid) do
    socket.assigns.seed_forms
    |> Map.fetch!(uid)
    |> Map.fetch!(:source)
    |> Changeset.get_assoc(:block)
  end

  defp child_descriptions(block_cs) do
    block_cs
    |> Changeset.get_assoc(:children)
    |> Enum.map(&Changeset.get_field(&1, :description))
  end

  test "recovers a new root block's children", %{user: user, page: page, module: module} do
    params = %{
      "rootUids" => ["rootA"],
      "currentUids" => [],
      "missingUids" => ["rootA"],
      "childOrder" => %{"rootA" => ["childA", "childB"]},
      "forms" => %{
        "entry_block_form-rootA" => root_form_params("rootA", module, user),
        "child_block_form-childA" => child_form_params("childA", module, user, description: "first"),
        "child_block_form-childB" => child_form_params("childB", module, user, description: "second")
      }
    }

    assert {:reply, %{recovered: ["rootA"]}, socket} =
             BlockField.handle_event("recover_blocks", params, socket(user, page))

    block_cs = recovered_block(socket, "rootA")

    assert Changeset.get_field(block_cs, :description) == "root description"
    assert child_descriptions(block_cs) == ["first", "second"]
  end

  test "preserves child order from childOrder, not map key order", %{
    user: user,
    page: page,
    module: module
  } do
    # A block's sequence is derived from its position in the children list, so
    # a reshuffle here silently reorders the user's blocks.
    params = %{
      "rootUids" => ["rootA"],
      "currentUids" => [],
      "missingUids" => ["rootA"],
      "childOrder" => %{"rootA" => ["childZ", "childA", "childM"]},
      "forms" => %{
        "entry_block_form-rootA" => root_form_params("rootA", module, user),
        "child_block_form-childA" => child_form_params("childA", module, user, description: "A"),
        "child_block_form-childM" => child_form_params("childM", module, user, description: "M"),
        "child_block_form-childZ" => child_form_params("childZ", module, user, description: "Z")
      }
    }

    assert {:reply, _, socket} =
             BlockField.handle_event("recover_blocks", params, socket(user, page))

    assert child_descriptions(recovered_block(socket, "rootA")) == ["Z", "A", "M"]
  end

  test "recovers grandchildren", %{user: user, page: page, module: module} do
    params = %{
      "rootUids" => ["rootA"],
      "currentUids" => [],
      "missingUids" => ["rootA"],
      "childOrder" => %{"rootA" => ["childA"], "childA" => ["grandA"]},
      "forms" => %{
        "entry_block_form-rootA" => root_form_params("rootA", module, user),
        "child_block_form-childA" => child_form_params("childA", module, user, description: "child"),
        "child_block_form-grandA" => child_form_params("grandA", module, user, description: "grand")
      }
    }

    assert {:reply, _, socket} =
             BlockField.handle_event("recover_blocks", params, socket(user, page))

    block_cs = recovered_block(socket, "rootA")
    assert [child_cs] = Changeset.get_assoc(block_cs, :children)
    assert child_descriptions(child_cs) == ["grand"]
  end

  test "a root with no children still recovers", %{user: user, page: page, module: module} do
    params = %{
      "rootUids" => ["rootA"],
      "currentUids" => [],
      "missingUids" => ["rootA"],
      "childOrder" => %{},
      "forms" => %{"entry_block_form-rootA" => root_form_params("rootA", module, user)}
    }

    assert {:reply, %{recovered: ["rootA"]}, socket} =
             BlockField.handle_event("recover_blocks", params, socket(user, page))

    assert child_descriptions(recovered_block(socket, "rootA")) == []
  end

  test "a childOrder entry with no captured form is skipped, not crashed", %{
    user: user,
    page: page,
    module: module
  } do
    params = %{
      "rootUids" => ["rootA"],
      "currentUids" => [],
      "missingUids" => ["rootA"],
      "childOrder" => %{"rootA" => ["childA", "ghost"]},
      "forms" => %{
        "entry_block_form-rootA" => root_form_params("rootA", module, user),
        "child_block_form-childA" => child_form_params("childA", module, user, description: "only")
      }
    }

    assert {:reply, _, socket} =
             BlockField.handle_event("recover_blocks", params, socket(user, page))

    assert child_descriptions(recovered_block(socket, "rootA")) == ["only"]
  end

  test "the recovered subtree survives a real save", %{user: user, page: page, module: module} do
    params = %{
      "rootUids" => ["rootA"],
      "currentUids" => [],
      "missingUids" => ["rootA"],
      "childOrder" => %{"rootA" => ["childA", "childB"]},
      "forms" => %{
        "entry_block_form-rootA" => root_form_params("rootA", module, user),
        "child_block_form-childA" => child_form_params("childA", module, user, description: "first"),
        "child_block_form-childB" => child_form_params("childB", module, user, description: "second")
      }
    }

    assert {:reply, _, socket} =
             BlockField.handle_event("recover_blocks", params, socket(user, page))

    # Recovery is only worth anything if what it rebuilt reaches the database.
    # The op store is what the save path reads, so materialize from there rather
    # than re-using the changeset built above.
    assert {:ok, materialized} = Ops.materialize_root(socket.assigns.block_ops, "rootA")

    base_block = %Brando.Content.Block{
      vars: [],
      refs: [],
      table_rows: [],
      children: [],
      block_identifiers: []
    }

    entry_block =
      @block_module
      |> struct(%{})
      |> Map.put(:block, base_block)
      |> @block_module.changeset(Map.put(materialized, "entry_id", page.id), user.id, true)
      |> Brando.Repo.insert!()

    reloaded =
      Brando.Repo.preload(entry_block, [block: [children: [:vars, :refs]]], force: true)

    assert Enum.map(reloaded.block.children, & &1.description) == ["first", "second"]
  end
end

defmodule BrandoAdmin.Components.Form.Block.RefMediaTest do
  # Regression coverage for B1 — media picked on a *persisted* ref used to be
  # dropped by the very next keystroke, with no disconnect involved.
  #
  # `Block.commit_ref_data/2` is a pure `send_update`, and `update_ref_data`
  # writes the FK into the ref changeset's `changes` only. `render.ex` then
  # suppressed the FK hidden inputs once a ref had a primary key, so the value
  # had no DOM representation either. `validate_block`'s root clause rebases on
  # `changeset.data` (the DB refs) — so the pick reverted on the next `validate`.
  #
  # The fix has two halves and this file covers both:
  #   (a) `merge_programmatic_ref_media/2` folds the FKs back onto the DB base
  #   (b) the FK hidden inputs always render, so LiveView form recovery can
  #       replay them after the process dies
  use ExUnit.Case, async: false
  use Brando.ConnCase

  use Phoenix.Component

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Factory
  alias BrandoAdmin.Components.Form.Block.Events
  alias Ecto.Changeset
  alias Phoenix.Component

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    image_a = Factory.insert(:image, creator: user)
    image_b = Factory.insert(:image, creator: user)

    entry_block =
      %Brando.Pages.Page.Blocks{}
      |> Changeset.change(%{entry_id: page.id, sequence: 0})
      |> Changeset.put_assoc(:block, %{
        uid: "blockrefs1",
        type: :module,
        active: true,
        description: "before",
        source: "Elixir.Brando.Pages.Page.Blocks",
        creator_id: user.id,
        sequence: 0,
        refs: [
          %{
            name: "picture",
            uid: "pictureref",
            description: "a picture ref",
            sequence: 0,
            image_id: image_a.id
          }
        ]
      })
      |> Brando.Repo.insert!()

    entry_block =
      Brando.Repo.preload(entry_block, [
        :entry,
        block: [:vars, :refs, :table_rows, :block_identifiers, :children]
      ])

    {:ok, user: user, page: page, image_a: image_a, image_b: image_b, entry_block: entry_block}
  end

  # What the picker/drawer does: `update_ref_data` puts the new FK straight into
  # the ref changeset's changes and nils the now-stale preloaded assoc. Nothing
  # is written to the DB.
  defp pick_image(entry_block, image_id) do
    [ref] = entry_block.block.refs

    ref_cs =
      ref
      |> Changeset.change()
      |> Changeset.put_change(:image_id, image_id)
      |> then(&Map.put(&1, :data, Map.put(&1.data, :image, nil)))

    block_cs =
      entry_block.block
      |> Changeset.change()
      |> Changeset.put_assoc(:refs, [ref_cs])

    entry_block
    |> Changeset.change()
    |> Changeset.put_assoc(:block, block_cs)
  end

  defp socket_for(changeset, entry_block, user) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:form, to_form(changeset, as: "entry_block", id: "entry_block_form-blockrefs1"))
    |> Component.assign(:uid, "blockrefs1")
    |> Component.assign(:block_module, Brando.Pages.Page.Blocks)
    |> Component.assign(:current_user_id, user.id)
    |> Component.assign(:entry, entry_block.entry)
    |> Component.assign(:has_vars?, false)
    |> Component.assign(:has_children?, false)
    |> Component.assign(:has_table_rows?, false)
    |> Component.assign(:live_preview_active?, false)
    |> Component.assign(:original_block_identifiers, [])
    |> Component.assign(:form_id, "page_form")
    |> Component.assign(:block_field, "blocks")
    |> Component.assign(:belongs_to, :root)
  end

  # The params a keystroke in the block's description sends. `ref_params` lets a
  # test choose whether the ref's media FK is present in the DOM payload.
  defp validate_params(ref, ref_params) do
    %{
      "_target" => ["entry_block", "block", "description"],
      "entry_block" => %{
        "block" => %{
          "uid" => "blockrefs1",
          "type" => "module",
          "description" => "after",
          "refs" => %{
            "0" => Map.merge(%{"id" => to_string(ref.id), "_persistent_id" => "0"}, ref_params)
          }
        }
      }
    }
  end

  defp resulting_ref(socket) do
    [ref] =
      socket.assigns.form.source
      |> Changeset.apply_changes()
      |> Map.fetch!(:block)
      |> Map.fetch!(:refs)

    ref
  end

  describe "(a) steady state — no DOM backing for the FK" do
    test "a pick on a persisted ref survives the next keystroke", ctx do
      %{entry_block: entry_block, user: user, image_a: image_a, image_b: image_b} = ctx

      changeset = pick_image(entry_block, image_b.id)
      [ref] = entry_block.block.refs

      # sanity: the pick is in `changes` only — the DB row still points at image_a
      assert Changeset.apply_changes(changeset).block.refs |> hd() |> Map.get(:image_id) == image_b.id
      assert Brando.Repo.get(Brando.Content.Ref, ref.id).image_id == image_a.id

      socket = socket_for(changeset, entry_block, user)

      # params deliberately omit image_id — this is the payload shape that used
      # to lose the pick, and any params that simply don't mention the FK
      assert {:halt, socket} =
               Events.handle_block_event("validate_block", validate_params(ref, %{}), socket)

      assert resulting_ref(socket).image_id == image_b.id,
             "the picked image must not revert to the DB value"

      # the keystroke itself still landed
      assert Changeset.apply_changes(socket.assigns.form.source).block.description == "after"
    end

    test "clearing a ref's image survives the next keystroke", ctx do
      %{entry_block: entry_block, user: user} = ctx

      changeset = pick_image(entry_block, nil)
      [ref] = entry_block.block.refs
      socket = socket_for(changeset, entry_block, user)

      assert {:halt, socket} =
               Events.handle_block_event("validate_block", validate_params(ref, %{}), socket)

      assert resulting_ref(socket).image_id == nil
    end

    test "an untouched ref keeps its persisted image", ctx do
      %{entry_block: entry_block, user: user, image_a: image_a} = ctx

      [ref] = entry_block.block.refs
      changeset = Changeset.change(entry_block)
      socket = socket_for(changeset, entry_block, user)

      assert {:halt, socket} =
               Events.handle_block_event("validate_block", validate_params(ref, %{}), socket)

      assert resulting_ref(socket).image_id == image_a.id
    end

    test "params still win over the merged value when they carry the FK", ctx do
      %{entry_block: entry_block, user: user, image_a: image_a, image_b: image_b} = ctx

      # in-memory pick says image_b, the DOM says image_a — the DOM is newer
      changeset = pick_image(entry_block, image_b.id)
      [ref] = entry_block.block.refs
      socket = socket_for(changeset, entry_block, user)

      params = validate_params(ref, %{"image_id" => to_string(image_a.id)})

      assert {:halt, socket} = Events.handle_block_event("validate_block", params, socket)
      assert resulting_ref(socket).image_id == image_a.id
    end

    test "the merged pick persists through a save", ctx do
      %{entry_block: entry_block, user: user, image_b: image_b} = ctx

      changeset = pick_image(entry_block, image_b.id)
      [ref] = entry_block.block.refs
      socket = socket_for(changeset, entry_block, user)

      assert {:halt, socket} =
               Events.handle_block_event("validate_block", validate_params(ref, %{}), socket)

      assert {:ok, _} =
               socket.assigns.form.source
               |> Map.put(:action, nil)
               |> Brando.Repo.update()

      assert Brando.Repo.get(Brando.Content.Ref, ref.id).image_id == image_b.id
    end
  end

  describe "(b) DOM backing — recoverability" do
    test "a persisted ref renders its media FK hidden inputs", ctx do
      %{entry_block: entry_block, image_a: image_a} = ctx

      html = render_ref(entry_block)

      assert html =~ ~s(name="entry_block[block][refs][0][image_id]")
      assert html =~ ~s(name="entry_block[block][refs][0][video_id]")
      assert html =~ ~s(name="entry_block[block][refs][0][gallery_id]")
      assert html =~ ~s(name="entry_block[block][refs][0][file_id]")

      # and it carries the current value, so recovery replays something real
      assert html =~ ~s(value="#{image_a.id}")
    end

    test "identity fields stay suppressed for a persisted ref", ctx do
      html = render_ref(ctx.entry_block)

      refute html =~ ~s(name="entry_block[block][refs][0][uid]")
      refute html =~ ~s(name="entry_block[block][refs][0][name]")
      refute html =~ ~s(name="entry_block[block][refs][0][description]")
    end

    # The real nesting: the root form is the entry_block, with the block (and so
    # the refs) one `inputs_for` down — which is what produces the
    # `entry_block[block][refs][0][…]` input names recovery keys on.
    defp entry_block_refs(assigns) do
      ~H"""
      <.form for={@form}>
        <.inputs_for :let={block_form} field={@form[:block]}>
          <BrandoAdmin.Components.Form.Block.Render.ref
            ref_name="picture"
            refs_field={block_form[:refs]}
            target={nil}
            form_id="page_form"
          />
        </.inputs_for>
      </.form>
      """
    end

    defp render_ref(entry_block) do
      form = to_form(Changeset.change(entry_block), as: "entry_block")
      render_component(&entry_block_refs/1, form: form)
    end
  end
end

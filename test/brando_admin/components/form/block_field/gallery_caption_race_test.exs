defmodule BrandoAdmin.Components.Form.BlockField.GalleryCaptionRaceTest do
  # A gallery block holding one image twice keeps a caption for each
  # placement, keyed by the placement's position among the image's
  # placements. One editor reorders the copies while another edits the
  # caption of one of them: in whichever order the edit session takes the two
  # changes, the caption stays with the copy it was written for, and each
  # copy keeps its own.
  use Brando.ConnCase, async: true

  alias Brando.Content.Ref
  alias Brando.Factory
  alias Brando.Drafts.Params
  alias Brando.Galleries.Gallery
  alias Brando.Villain.Blocks.GalleryObjectOverride
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Gallery"},
          namespace: %{"en" => "Content"},
          help_text: %{"en" => "Help"},
          code: "{% ref refs.gallery %}",
          refs: [%{name: "gallery", uid: Brando.Utils.generate_uid(), data: %{type: "gallery", data: %{}}}]
        ),
        user
      )

    image = Factory.insert(:image, creator: user)
    gallery = Factory.insert(:gallery)

    [first, second] =
      for sequence <- 0..1,
          do: Factory.insert(:gallery_object, gallery_id: gallery.id, image_id: image.id, sequence: sequence)

    page = Factory.insert(:page, creator: user)
    block = Brando.Test.insert_block(page, module, user: user, refs: %{"gallery" => gallery})

    ref = Repo.get_by!(Ref, block_id: block.id, name: "gallery")

    overrides =
      for {object, placement, title} <- [{first, 0, "First"}, {second, 1, "Second"}] do
        %GalleryObjectOverride{
          uid: GalleryObjectOverride.object_uid(object),
          object_id: to_string(image.id),
          object_type: :image,
          placement: placement,
          title: title,
          use_default_title: false
        }
      end

    data = %{ref.data | data: %{ref.data.data | gallery_object_overrides: overrides}}
    ref |> Changeset.change(data: data) |> Repo.update!()

    {:ok, user: user, page: page, image: image, first: first, second: second}
  end

  defp rows(page) do
    import Ecto.Query

    Brando.Pages.Page.Blocks
    |> where([eb], eb.entry_id == ^page.id)
    |> order_by([eb], eb.sequence)
    |> Repo.all()
    |> Repo.preload(block: [:vars, :table_rows, :block_identifiers, :children, refs: Ref.preloads()])
  end

  # The op the browser's change of the block's form makes: its params, as
  # the form submits them, changed by `change`.
  defp form_op(entry_block, user, change) do
    before = Changeset.change(entry_block)
    params = before |> Params.snapshot() |> update_in(["block", "refs"], fn [ref] -> [change.(as_form(ref))] end)
    changeset = Brando.Pages.Page.Blocks.changeset(entry_block, params, user.id)
    {:ok, op} = Ops.field_op(before, changeset, entry_block.block.uid)
    op
  end

  # The form names gallery objects by their index, as a map
  defp as_form(ref) do
    update_in(ref, ["gallery", "gallery_objects"], fn objects ->
      objects |> Enum.with_index() |> Map.new(fn {object, index} -> {to_string(index), object} end)
    end)
  end

  defp reorder(ref), do: put_in(ref, ["gallery", "sort_gallery_object_ids"], ["1", "0"])

  defp edit_first_caption(ref) do
    update_in(ref, ["data", "data", "gallery_object_overrides"], fn overrides ->
      Enum.map(overrides, fn override ->
        if override["placement"] == 0, do: Map.put(override, "title", "First, edited"), else: override
      end)
    end)
  end

  defp apply!(state, op) do
    {:ok, state} = Ops.apply_op(state, op)
    state
  end

  defp save(page, rows, ops, user) do
    by_uid = Map.new(rows, &{&1.block.uid, &1})

    updated =
      Enum.map(ops.order, fn uid ->
        {:ok, params} = Ops.materialize_root(ops, uid)
        Brando.Pages.Page.Blocks.changeset(by_uid[uid], params, user.id, true)
      end)
      |> Brando.Content.Blocks.reject_deleted(true)
      |> Brando.Content.Blocks.strip_render_artifacts()
      |> Enum.map(&Brando.Utils.set_action/1)

    page
    |> Repo.preload(:entry_blocks)
    |> Changeset.change()
    |> Changeset.put_assoc(:entry_blocks, updated)
    |> Repo.update!()
  end

  # Each gallery object in order, as `{object id, caption}`
  defp captions(page) do
    [row] = rows(page)
    [ref] = row.block.refs
    gallery = Repo.preload(Repo.get!(Gallery, ref.gallery_id), :gallery_objects, force: true)
    objects = Enum.sort_by(gallery.gallery_objects, & &1.sequence)
    index = GalleryObjectOverride.index(ref.data.data.gallery_object_overrides)

    objects
    |> Enum.map(&{:image, to_string(&1.image_id)})
    |> GalleryObjectOverride.placements()
    |> Enum.zip(objects)
    |> Enum.map(fn {{type, id, placement}, object} ->
      {object.id, GalleryObjectOverride.lookup(index, type, id, placement).title}
    end)
  end

  for order <- [:reorder_first, :caption_first] do
    test "a caption written while another editor reorders the copies stays with its copy (#{order})", c do
      rows = rows(c.page)
      [row] = rows

      reorder = form_op(row, c.user, &reorder/1)
      caption = form_op(row, c.user, &edit_first_caption/1)

      ops = if unquote(order) == :reorder_first, do: [reorder, caption], else: [caption, reorder]
      state = Enum.reduce(ops, Ops.from_entry_blocks(rows), &apply!(&2, &1))
      save(c.page, rows, state, c.user)

      assert captions(c.page) == [{c.second.id, "Second"}, {c.first.id, "First, edited"}]
    end
  end

end

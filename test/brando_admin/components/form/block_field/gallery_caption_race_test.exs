defmodule BrandoAdmin.Components.Form.BlockField.GalleryCaptionRaceTest do
  # A gallery block holding one image twice keeps a caption for each
  # placement, keyed by the placement's position among the image's
  # placements. One editor reorders the copies while another edits the
  # caption of one of them: in whichever order the edit session takes the two
  # changes, the caption stays with the copy it was written for, and each
  # copy keeps its own.
  use Brando.ConnCase, async: true

  alias Brando.Content.Ref
  alias Brando.Drafts.Params
  alias Brando.Factory
  alias Brando.Galleries.Gallery
  alias Brando.Villain.Blocks.GalleryObjectOverride
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Ecto.Changeset

  setup tags do
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
          # A copied gallery's overrides keep the uids of the gallery they were copied from
          uid: if(tags[:copied], do: "copied-#{placement}", else: GalleryObjectOverride.object_uid(object)),
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

  # The op the browser's change of the block's form makes: the form as it
  # was rendered, and as it is with `change` made to its params.
  defp form_op(entry_block, user, change) do
    params = entry_block |> Changeset.change() |> Params.snapshot()
    form = fn change -> update_in(params, ["block", "refs"], fn [ref] -> [change.(as_form(ref))] end) end
    before = Brando.Pages.Page.Blocks.changeset(entry_block, form.(& &1), user.id)
    changeset = Brando.Pages.Page.Blocks.changeset(entry_block, form.(change), user.id)
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

  defp edit_first_caption(ref),
    do: update_in(ref, ["data", "data", "gallery_object_overrides"], &Enum.map(&1, fn o -> caption_at_zero(o) end))

  defp caption_at_zero(%{"placement" => 0} = override), do: Map.put(override, "title", "First, edited")
  defp caption_at_zero(override), do: override

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
      {object.id, index |> GalleryObjectOverride.lookup(type, id, placement) |> then(&(&1 && &1.title))}
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

  defp remove_first(ref), do: put_in(ref, ["gallery", "drop_gallery_object_ids"], ["0"])

  for order <- [:remove_first, :caption_first] do
    test "a caption written for a copy another editor removes goes with it (#{order})", c do
      rows = rows(c.page)
      [row] = rows

      remove = form_op(row, c.user, &remove_first/1)
      caption = form_op(row, c.user, &edit_first_caption/1)

      ops = if unquote(order) == :remove_first, do: [remove, caption], else: [caption, remove]
      state = Enum.reduce(ops, Ops.from_entry_blocks(rows), &apply!(&2, &1))
      save(c.page, rows, state, c.user)

      assert captions(c.page) == [{c.second.id, "Second"}]
    end
  end

  defp remove_second(ref), do: put_in(ref, ["gallery", "drop_gallery_object_ids"], ["1"])

  # The reorder gives the first copy the second placement; the removal leaves
  # it the only copy. Saved, its caption has the placement its copy has.
  #
  # Arriving after the removal, the reorder brings the removed copy back: it
  # moved it, which the session's merge of the gallery's objects takes for a
  # change. That copy's caption went with the removal.
  for {order, expected} <- [reorder_first: [:first], remove_first: [:second, :first]] do
    test "a copy left alone while another editor reordered keeps its caption (#{order})", c do
      rows = rows(c.page)
      [row] = rows

      reorder = form_op(row, c.user, &reorder/1)
      remove = form_op(row, c.user, &remove_second/1)

      ops = if unquote(order) == :reorder_first, do: [reorder, remove], else: [remove, reorder]
      state = Enum.reduce(ops, Ops.from_entry_blocks(rows), &apply!(&2, &1))
      save(c.page, rows, state, c.user)

      titles = %{first: {c.first.id, "First"}, second: {c.second.id, nil}}
      assert captions(c.page) == Enum.map(unquote(expected), &titles[&1])
    end
  end

  # The copies were reordered and saved before: the overrides are stored in
  # the order they had, not the copies'. Reordered back while a caption is
  # written, each copy keeps its own.
  for order <- [:reorder_first, :caption_first] do
    test "a second reorder meets a caption edit (#{order})", c do
      rows = rows(c.page)
      [row] = rows
      save(c.page, rows, apply!(Ops.from_entry_blocks(rows), form_op(row, c.user, &reorder/1)), c.user)
      assert captions(c.page) == [{c.second.id, "Second"}, {c.first.id, "First"}]

      rows = rows(c.page)
      [row] = rows
      reorder = form_op(row, c.user, &reorder/1)
      caption = form_op(row, c.user, &edit_first_caption/1)

      ops = if unquote(order) == :reorder_first, do: [reorder, caption], else: [caption, reorder]
      state = Enum.reduce(ops, Ops.from_entry_blocks(rows), &apply!(&2, &1))
      save(c.page, rows, state, c.user)

      # The caption written at placement 0, which was the second copy
      assert captions(c.page) == [{c.first.id, "First"}, {c.second.id, "First, edited"}]
    end
  end

  # A copied gallery keeps its overrides' uids, which name the objects of the
  # gallery it was copied from. The removal leaves one copy, whose caption
  # goes with it whatever placement the reorder gave it.
  for order <- [:reorder_first, :remove_first] do
    @tag copied: true
    test "in a copied gallery, a copy left alone while another editor reordered keeps its caption (#{order})", c do
      rows = rows(c.page)
      [row] = rows

      reorder = form_op(row, c.user, &reorder/1)
      remove = form_op(row, c.user, &remove_second/1)

      ops = if unquote(order) == :reorder_first, do: [reorder, remove], else: [remove, reorder]
      state = Enum.reduce(ops, Ops.from_entry_blocks(rows), &apply!(&2, &1))
      save(c.page, rows, state, c.user)

      assert {c.first.id, "First"} in captions(c.page)
    end
  end
end

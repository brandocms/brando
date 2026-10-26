defmodule BrandoAdmin.Components.Form.EntryPictureBlockSyncTest do
  # A block whose module previews the entry's own picture (`{% picture
  # entry.meta_image {…} %}`) is on the form's entry fan-out for that field.
  # Picking, uploading, removing or resetting the image in the form commits the
  # relation's id; the block reads the relation, so the form delivers the
  # relation itself, and the preview follows.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 1]

  alias Brando.Blueprint.Forms, as: BlueprintForms
  alias Brando.Factory
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Block
  alias Ecto.Changeset
  alias Phoenix.Component

  @code ~s(<header>{% picture entry.meta_image {size: "xlarge"} %}</header>)
  @block_ref {Block, "block-preview"}

  setup do
    user = Factory.insert(:random_user)
    first = Factory.insert(:image, creator: user, path: "images/meta/first.jpg")
    second = Factory.insert(:image, creator: user, path: "images/meta/second.jpg")
    page = Factory.insert(:page, creator: user, meta_image_id: first.id)
    page = %{page | meta_image: first}
    {:ok, user: user, page: page, first: first, second: second}
  end

  defp form_socket(page, user, edit_image) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:form, to_form(Changeset.change(page)))
    |> Component.assign(:entry, page)
    |> Component.assign(:schema, Brando.Pages.Page)
    |> Component.assign(:singular, "page")
    |> Component.assign(:current_user, user)
    |> Component.assign(:processing_images, [])
    |> Component.assign(:editing_image?, false)
    |> Component.assign(:editing_video?, false)
    |> Component.assign(:editing_file?, false)
    |> Component.assign(:edit_image, edit_image)
    |> Component.assign(:edit_video, nil)
    |> Component.assign(:edit_file, nil)
    |> Component.assign(:updated_entry_assocs, %{})
    |> Component.assign(:blocks_wanting_entry, %{@block_ref => ["meta_image"]})
  end

  defp block_socket(page) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:entry, page)
    |> Component.assign(:liquid_splits, Block.liquid_splits(@code, [], page))
  end

  defp preview_src(block_socket) do
    Enum.find_value(block_socket.assigns.liquid_splits, fn
      {:entry_picture, "entry.meta_image", src} -> src
      _ -> nil
    end)
  end

  # What the form sent the block, applied as LiveView would
  defp deliver_to_block(block_socket) do
    assert_received {:phoenix, :send_update, {@block_ref, %{event: "update_entry_field"} = update}}
    {:ok, block_socket} = Block.update(update, block_socket)
    block_socket
  end

  test "picking another image moves the block's preview to it", ctx do
    %{page: page, user: user, second: second} = ctx
    block = block_socket(page)
    assert preview_src(block) =~ "first.jpg"

    edit_image = %{path: [], field: :meta_image, relation_field: :meta_image_id, image: nil}

    {:ok, _form} =
      Form.update(
        %{event: "entry_field_upload_complete", asset_type: :image, field: :meta_image, path: [], asset: second},
        form_socket(page, user, edit_image)
      )

    assert block |> deliver_to_block() |> preview_src() =~ "second.jpg"
  end

  # The live preview merges `updated_entry_assocs` over the entry, so an image
  # picked earlier would hide the one uploaded now.
  test "an upload replaces the image the preview shows", ctx do
    %{page: page, user: user, first: first, second: second} = ctx
    edit_image = %{path: [], field: :meta_image, relation_field: :meta_image_id, image: first}
    socket = page |> form_socket(user, edit_image) |> Component.assign(:updated_entry_assocs, %{meta_image: first})

    {:ok, form} =
      Form.update(
        %{event: "entry_field_upload_complete", asset_type: :image, field: :meta_image, path: [], asset: second},
        socket
      )

    assert form.assigns.updated_entry_assocs == %{meta_image: second}
  end

  # The drawer's save changes the image the field shows; the preview's copy
  # of it follows, or the title edited there never reaches the preview.
  test "saving the image's drawer refreshes the image the preview shows", ctx do
    %{page: page, user: user} = ctx
    image = Factory.insert(:image, creator: user, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)
    edit_image = %{path: [], field: :meta_image, relation_field: :meta_image_id, image: image}

    socket =
      page
      |> form_socket(user, edit_image)
      |> Component.assign(sync_assigns())
      |> Component.assign(:updated_entry_assocs, %{meta_image: image})

    params = %{"image" => %{"title" => %{"en" => "Example Hotel lobby"}}}
    {:noreply, form} = Form.handle_event("save_image", params, socket)

    assert form.assigns.updated_entry_assocs.meta_image.title == %{"en" => "Example Hotel lobby"}
  end

  # The drawer edits the image's texts (and focal point); the rest of the image
  # (its path, which the crop editor writes to, and its sizes) is not the
  # drawer's to change, whatever the params say.
  test "saving the image's drawer takes only what the drawer edits", ctx do
    %{page: page, user: user} = ctx
    image = Factory.insert(:image, creator: user, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)
    edit_image = %{path: [], field: :meta_image, relation_field: :meta_image_id, image: image}

    socket =
      page
      |> form_socket(user, edit_image)
      |> Component.assign(sync_assigns())
      |> Component.assign(:updated_entry_assocs, %{meta_image: image})

    params = %{
      "image" => %{
        "title" => %{"en" => "Lobby"},
        "path" => "images/elsewhere.jpg",
        "sizes" => %{"thumb" => "images/elsewhere.jpg"},
        "config_target" => "image:Elsewhere:cover"
      }
    }

    {:noreply, _form} = Form.handle_event("save_image", params, socket)

    saved = Repo.get!(Brando.Images.Image, image.id)
    assert saved.title["en"] == "Lobby"
    assert {saved.path, saved.sizes, saved.config_target} == {image.path, image.sizes, image.config_target}
  end

  # A block opens the image editor, not the drawer, so a drawer save with
  # the block's image in `edit_image` has nothing to save: it closes, and
  # neither changes the image nor makes one.
  test "a drawer save with a block's image closes without saving", ctx do
    %{page: page, user: user} = ctx
    image = Factory.insert(:image, creator: user, status: :processed, title: %{"en" => "Lobby"})

    edit_image = %{
      path: [],
      field: nil,
      relation_field: nil,
      image: image,
      block_target: @block_ref,
      old_image_id: image.id
    }

    count = Repo.aggregate(Brando.Images.Image, :count)

    params = %{"image" => %{"title" => %{"en" => "Lobby, edited"}}}
    socket = page |> form_socket(user, edit_image) |> Component.assign(:editing_image?, true)
    {:noreply, form} = Form.handle_event("save_image", params, socket)

    refute form.assigns.editing_image?
    assert Repo.aggregate(Brando.Images.Image, :count) == count
    assert Repo.get!(Brando.Images.Image, image.id).title == %{"en" => "Lobby"}
    refute_received {:phoenix, :send_update, _}
  end

  # The drawer's save is reported as the image's id (`b:validate`), which a
  # trigger declared on the image field does not cover.
  test "saving the image's drawer fires the preview trigger declared on the field", ctx do
    %{page: page, user: user} = ctx
    image = Factory.insert(:image, creator: user, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)
    edit_image = %{path: [], field: :meta_image, relation_field: :meta_image_id, image: image}

    socket =
      page
      |> form_socket(user, edit_image)
      |> Component.assign(sync_assigns())
      |> Component.assign(
        id: "page_form",
        live_preview_active?: true,
        preview_update: nil,
        fields_demanding_full_live_preview_rerender: [[:meta_image]],
        fields_demanding_live_preview_reassign: []
      )

    params = %{"image" => %{"title" => %{"en" => "Example Hotel lobby"}}}
    {:noreply, form} = Form.handle_event("save_image", params, socket)

    assert form.assigns.preview_update.mode == :live_preview_full_rerender
    # the render it queues may come before the browser's `validate`
    assert form.assigns.form.source.data.meta_image.title == %{"en" => "Example Hotel lobby"}
  end

  # Each drawer's save puts the saved asset in the changeset, at the top level
  # and in a subform row (a page variable's image, file or video): the render
  # it queues may come before the browser's `validate`.
  describe "a drawer's save puts the saved asset in the changeset" do
    setup %{user: user} do
      image = Factory.insert(:image, creator: user, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)
      file = Repo.insert!(%Brando.Files.File{filename: "rates.pdf", filesize: 1, config_target: "default"})
      video = Factory.insert(:video, creator: user)
      {:ok, saved_image: image, saved_file: file, saved_video: video}
    end

    defp drawer_socket(page, user, kind, path, field, asset) do
      edit = Map.put(%{path: path, field: field, relation_field: :"#{field}_id"}, kind, asset)

      page
      |> form_socket(user, nil)
      |> Component.assign(sync_assigns())
      |> Component.assign(:"edit_#{kind}", edit)
      |> Component.assign(:"#{kind}_changeset", nil)
    end

    defp in_row(page, field, asset) do
      var = %Brando.Content.Var{id: 1, key: "hero", type: field, label: "Hero"}
      %{page | vars: [Map.merge(var, %{field => asset, :"#{field}_id" => asset.id})]}
    end

    defp saved(form, []), do: form.assigns.form.source.data
    defp saved(form, [:vars, 0]), do: form.assigns.form.source |> Changeset.apply_changes() |> Map.get(:vars) |> hd()

    defp with_image(page, [], image), do: {%{page | meta_image: image}, :meta_image}
    defp with_image(page, _row, image), do: {in_row(page, :image, image), :image}

    for path <- [[], [:vars, 0]] do
      test "for an image at #{inspect(path)}", %{page: page, user: user, saved_image: image} do
        path = unquote(path)
        {page, field} = with_image(page, path, image)
        socket = drawer_socket(page, user, :image, path, field, image)

        params = %{"image" => %{"title" => %{"en" => "Example Hotel lobby"}}}
        {:noreply, form} = Form.handle_event("save_image", params, socket)

        assert Map.get(saved(form, path), field).title == %{"en" => "Example Hotel lobby"}
      end
    end

    test "for an image in a one-to-one subform", %{page: page, user: user, saved_image: image} do
      article = %Brando.SyncTest.Article{id: 1, author: %Brando.SyncTest.ArticleAuthor{id: 1, portrait: image}}

      socket =
        page
        |> drawer_socket(user, :image, [:author], :portrait, image)
        |> Component.assign(schema: Brando.SyncTest.Article, entry: article, singular: "article")
        |> Component.assign(:form, to_form(Changeset.change(article)))

      params = %{"image" => %{"title" => %{"en" => "Example Hotel lobby"}}}
      {:noreply, form} = Form.handle_event("save_image", params, socket)

      assert Changeset.apply_changes(form.assigns.form.source).author.portrait.title == %{"en" => "Example Hotel lobby"}
    end

    # A removed row stays in the relation, first, as a row being replaced; the
    # form does not count it (`struct_at/2`), so the row shown at 0 is the
    # second in the relation.
    for {event, socket_event} <- [{"clear_entry_field_asset", :update}, {"reset_image_field", :handle_event}] do
      test "#{event} after a removed row clears the row shown", %{page: page, user: user, saved_image: image} do
        removed = %Brando.Content.Var{id: 2, key: "old", type: :text, label: "Old"}
        page = in_row(page, :image, image)
        [shown] = page.vars
        page = %{page | vars: [removed, shown]}
        changeset = page |> Changeset.change() |> Changeset.put_assoc(:vars, [shown])

        socket =
          page
          |> drawer_socket(user, :image, [:vars, 0], :image, image)
          |> Component.assign(:form, to_form(changeset))

        form =
          case unquote(socket_event) do
            :update ->
              {:ok, form} = Form.update(%{event: unquote(event), field: :image, path: [:vars, 0]}, socket)
              form

            :handle_event ->
              {:noreply, form} = Form.handle_event(unquote(event), %{}, socket)
              form
          end

        rows = form.assigns.form.source.changes.vars
        assert %Changeset{action: :replace} = Enum.find(rows, &(&1.data.id == removed.id))
        row = Enum.find(rows, &(&1.data.id == shown.id))
        assert Changeset.get_field(row, :image_id) == nil
        assert Changeset.apply_changes(row).image == nil
      end
    end

    # The same rows: a removed one pending, first, and the one the form shows at 0.
    defp with_removed_row(page, image, socket_fun) do
      removed = %Brando.Content.Var{id: 2, key: "old", type: :text, label: "Old"}
      page = in_row(page, :image, image)
      [shown] = page.vars
      page = %{page | vars: [removed, shown]}
      changeset = page |> Changeset.change() |> Changeset.put_assoc(:vars, [shown])
      socket = page |> socket_fun.() |> Component.assign(:form, to_form(changeset))
      {socket, removed, shown}
    end

    defp row(form, id), do: Enum.find(form.assigns.form.source.changes.vars, &(&1.data.id == id))

    test "a gallery put in a row after a removed row goes on the row shown", %{page: page, user: user, saved_image: image} do
      {socket, removed, shown} =
        with_removed_row(page, image, &drawer_socket(&1, user, :image, [:vars, 0], :image, image))

      gallery = %Brando.Galleries.Gallery{config_target: "default", gallery_objects: []}

      {:ok, form} = Form.update(%{action: :put_gallery, path: [:vars, 0], key: :gallery, gallery: gallery}, socket)

      assert %Changeset{action: :replace} = row(form, removed.id)
      assert %Changeset{} = row(form, shown.id).changes.gallery
    end

    # A path older than the rows (one removed since) names no row the form shows.
    test "clearing an image at a row the form no longer shows changes nothing", %{
      page: page,
      user: user,
      saved_image: image
    } do
      {socket, removed, shown} =
        with_removed_row(page, image, &drawer_socket(&1, user, :image, [:vars, 1], :image, image))

      {:ok, form} = Form.update(%{event: "clear_entry_field_asset", field: :image, path: [:vars, 1]}, socket)

      assert %Changeset{action: :replace, changes: changes} = row(form, removed.id)
      refute Map.has_key?(changes, :image_id)
      assert Changeset.get_field(row(form, shown.id), :image_id) == image.id
    end

    # The upload is delivered only while the field still holds what it held
    # when the upload began: the row the form shows, not the removed one.
    test "an upload to a row after a removed row is delivered to it", %{page: page, user: user, saved_image: image} do
      {socket, _removed, shown} =
        with_removed_row(page, image, &drawer_socket(&1, user, :image, [:vars, 0], :image, image))

      uploaded = Factory.insert(:image, creator: user, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)

      event = %{
        event: "entry_field_upload_complete",
        expected_asset_id: image.id,
        asset_type: :image,
        field: :image,
        path: [:vars, 0],
        asset: uploaded
      }

      {:ok, form} = Form.update(event, socket)

      row = form.assigns.form.source |> Changeset.apply_changes() |> Map.get(:vars) |> Enum.find(&(&1.id == shown.id))
      assert row.image_id == uploaded.id
    end

    test "for a file", %{page: page, user: user, saved_file: file} do
      socket = drawer_socket(in_row(page, :file, file), user, :file, [:vars, 0], :file, file)

      {:noreply, form} = Form.handle_event("save_file", %{"file" => %{"title" => "Example Hotel rates"}}, socket)

      assert saved(form, [:vars, 0]).file.title == "Example Hotel rates"
    end

    test "for a video", %{page: page, user: user, saved_video: video} do
      socket = drawer_socket(in_row(page, :video, video), user, :video, [:vars, 0], :video, video)

      {:noreply, form} = Form.handle_event("save_video", %{"video" => %{"title" => "Example Hotel tour"}}, socket)

      assert saved(form, [:vars, 0]).video.title == "Example Hotel tour"
    end
  end

  # The next `validate` casts onto the entry, so a remote image has to be on
  # it too, or the form and the preview go back to the old one.
  test "another editor's pick goes on the entry this editor's next change casts onto", ctx do
    %{page: page, user: user, second: second} = ctx
    socket = page |> form_socket(user, nil) |> Component.assign(sync_assigns())
    changes = [%{field: :meta_image_id, value: second.id, assoc?: false, clock: {1, "remote"}}]

    {:ok, form} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket)

    assert form.assigns.entry.meta_image.id == second.id
  end

  defmodule UriLink do
    use Ecto.Schema

    schema "example_links" do
      belongs_to :page, Brando.Pages.Page, foreign_key: :page_uri, references: :uri, type: :string
    end
  end

  # A relation that references a column other than the primary key is
  # loaded by that column.
  test "another editor's pick of a relation by another column loads it by that column", ctx do
    %{page: page, user: user} = ctx
    link = %UriLink{id: 1, page_uri: page.uri, page: page}

    socket =
      page
      |> form_socket(user, nil)
      |> Component.assign(sync_assigns())
      |> Component.assign(schema: UriLink, entry: link, singular: "uri_link")
      |> Component.assign(:form, to_form(Changeset.change(link)))

    target = Factory.insert(:page, creator: user, title: "Example Hotel", uri: "example-hotel")
    changes = [%{field: :page_uri, value: "example-hotel", assoc?: false, clock: {1, "remote"}}]

    {:ok, form} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket)

    assert form.assigns.updated_entry_assocs.page.id == target.id
  end

  # The preview merges a relation this editor picked (a select with
  # `update_relation`) over the entry, and otherwise preloads only a relation
  # not loaded yet; another editor's pick replaces both.
  for {held, page_parent} <- [{"one this editor picked", :not_loaded}, {"a loaded one", :loaded}] do
    test "another editor's pick replaces #{held}", ctx do
      %{page: page, user: user} = ctx
      parent = Factory.insert(:page, creator: user, title: "Example Hotel")

      {page, assocs} =
        if unquote(page_parent) == :loaded, do: {%{page | parent: nil}, %{}}, else: {page, %{parent: nil}}

      socket =
        page
        |> form_socket(user, nil)
        |> Component.assign(sync_assigns())
        |> Component.assign(:updated_entry_assocs, assocs)

      changes = [%{field: :parent_id, value: parent.id, assoc?: false, clock: {1, "remote"}}]

      {:ok, form} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket)

      assert form.assigns.updated_entry_assocs.parent.id == parent.id
    end
  end

  # A select with `update_relation` puts what its fetcher returns on the
  # relation (preloads included); another editor's pick is fetched the same way.
  test "another editor's pick of a relation a select sets is fetched by that select's fetcher", ctx do
    %{page: page, user: user} = ctx
    parent = Factory.insert(:page, creator: user, title: "Example Hotel")
    test_pid = self()

    fetcher = fn id ->
      send(test_pid, {:fetched, id})
      {:ok, %{Repo.get!(Brando.Pages.Page, id) | title: "Example Hotel, as fetched"}}
    end

    input = %BlueprintForms.Input{name: :parent_id, type: :select, opts: [update_relation: {:parent, fetcher}]}
    blueprint = %BlueprintForms.Form{tabs: [%BlueprintForms.Tab{fields: [%BlueprintForms.Fieldset{fields: [input]}]}]}

    socket =
      page
      |> form_socket(user, nil)
      |> Component.assign(sync_assigns())
      |> Component.assign(form_blueprint: blueprint, updated_entry_assocs: %{parent: nil})

    changes = [%{field: :parent_id, value: parent.id, assoc?: false, clock: {1, "remote"}}]

    {:ok, form} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket)

    parent_id = to_string(parent.id)
    assert_received {:fetched, ^parent_id}
    assert form.assigns.updated_entry_assocs.parent.title == "Example Hotel, as fetched"
  end

  test "another editor's pick of a relation its fetcher cannot find leaves the relation empty", ctx do
    %{page: page, user: user} = ctx
    fetcher = &Brando.Pages.get_page!/1
    input = %BlueprintForms.Input{name: :parent_id, type: :select, opts: [update_relation: {:parent, fetcher}]}
    blueprint = %BlueprintForms.Form{tabs: [%BlueprintForms.Tab{fields: [%BlueprintForms.Fieldset{fields: [input]}]}]}

    socket =
      page
      |> form_socket(user, nil)
      |> Component.assign(sync_assigns())
      |> Component.assign(form_blueprint: blueprint, updated_entry_assocs: %{parent: page})

    changes = [%{field: :parent_id, value: page.id + 1_000_000, assoc?: false, clock: {1, "remote"}}]

    {:ok, form} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket)

    assert form.assigns.updated_entry_assocs.parent == nil
  end

  defp sync_assigns do
    [
      tiptap_epoch: "mounted-form",
      dirty_fields: [],
      synced_values: %{},
      unshipped_fields: MapSet.new(),
      replaced_values: %{},
      held_remote: %{},
      field_clocks: %{},
      live_preview_active?: false
    ]
  end

  # Another editor's pick arrives as the image's id (`apply_remote/2`); the
  # block reads the relation, so that is what it gets.
  test "another editor's pick moves the block's preview to it", ctx do
    %{page: page, user: user, second: second} = ctx
    block = block_socket(page)
    socket = page |> form_socket(user, nil) |> Component.assign(sync_assigns())

    changes = [%{field: :meta_image_id, value: second.id, assoc?: false, clock: {1, "remote"}}]

    {:ok, _form} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket)

    assert block |> deliver_to_block() |> preview_src() =~ "second.jpg"
  end

  test "removing the image clears the block's preview", ctx do
    %{page: page, user: user} = ctx
    block = block_socket(page)

    {:ok, _form} =
      Form.update(%{event: "clear_entry_field_asset", field: :meta_image, path: []}, form_socket(page, user, nil))

    assert block |> deliver_to_block() |> preview_src() == ""
  end

  test "resetting the image in its drawer clears the block's preview", ctx do
    %{page: page, user: user, first: first} = ctx
    block = block_socket(page)
    edit_image = %{path: [], field: :meta_image, relation_field: :meta_image_id, image: first}

    {:noreply, _form} = Form.handle_event("reset_image_field", %{}, form_socket(page, user, edit_image))

    assert block |> deliver_to_block() |> preview_src() == ""
  end
end

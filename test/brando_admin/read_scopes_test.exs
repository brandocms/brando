# An entry with a join list of pages, as a case has of its categories.
defmodule BrandoAdmin.ReadScopesTest.Shelf do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "ReadScopesTest",
    schema: "Shelf",
    singular: "shelf",
    plural: "shelves",
    gettext_module: Brando.Gettext

  table "read_scopes_shelves"

  relations do
    relation :shelved_pages, :has_many, module: BrandoAdmin.ReadScopesTest.ShelvedPage, cast: true
  end
end

defmodule BrandoAdmin.ReadScopesTest.ShelvedPage do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "ReadScopesTest",
    schema: "ShelvedPage",
    singular: "shelved_page",
    plural: "shelved_pages",
    gettext_module: Brando.Gettext

  table "read_scopes_shelved_pages"

  relations do
    relation :shelf, :belongs_to, module: BrandoAdmin.ReadScopesTest.Shelf
    relation :page, :belongs_to, module: Brando.Pages.Page
  end
end

defmodule BrandoAdmin.ReadScopesTest do
  # Reads that name another entry answer for the viewer: an account that may
  # read the entry sees what it always did, and one that may not learns that
  # something is there, never what. Legacy mode has no read narrowing.
  use Brando.LiveCase

  import Brando.Test.Users

  alias Brando.Authorization.{Boundary, Catalog, Engine, Scope}
  alias Brando.Content.Block
  alias Brando.Content.Proposals.{EntryFields, Tools}
  alias Brando.Content.Proposals.Tools.Context
  alias Brando.Content.Usage
  alias Brando.Images.Image
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.SyncTest.Article
  alias Brando.Tenant
  alias Brando.Users.User
  alias BrandoAdmin.Components.Content.SelectIdentifier
  alias BrandoAdmin.Components.Form.Input.Blocks.TipTapLinkDialog
  alias BrandoAdmin.Images.FolderBrowser
  alias BrandoAdmin.Images.Sweep
  alias BrandoAdmin.LiveView.Listing.DeleteDescription
  alias BrandoAdmin.ReadScopesTest.Shelf
  alias Ecto.Adapters.SQL

  @secret "Secret page marker"
  @page_read ~w(brando.pages.read)

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    on_exit(fn -> Boundary.put_scope(nil) end)

    page = secret_page()
    {:ok, identifier} = Brando.Content.create_identifier(Page, page)
    %{page: page, identifier: identifier}
  end

  defp secret_page(title \\ @secret) do
    Factory.insert(:page, title: title, uri: "#{Brando.Utils.slugify(title)}-#{System.unique_integer([:positive])}")
  end

  # A block on `page` showing `image`.
  defp show(page, image) do
    source = "Elixir.Brando.Pages.Page.Blocks"
    block = Repo.insert!(%Block{type: :module, source: source, uid: Brando.Utils.generate_uid()})
    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    Factory.insert(:ref, block_id: block.id, image_id: image.id)
  end

  defp as(user), do: Boundary.put_scope(Scope.standalone(user))

  defp queries(fun) do
    test = self()
    id = "read-scopes-#{System.unique_integer([:positive])}"
    counter = :counters.new(1, [])

    :telemetry.attach(
      id,
      [:brando_integration, :repo, :query],
      fn _event, _measurements, _meta, _config -> if self() == test, do: :counters.add(counter, 1, 1) end,
      nil
    )

    try do
      fun.()
      :counters.get(counter, 1)
    after
      :telemetry.detach(id)
    end
  end

  describe "the entry link picker" do
    defp picker(extra \\ %{}) do
      props = Map.merge(%{id: "picker", layout: :workspace, require_url: true, wanted_schemas: [Page]}, extra)
      {:ok, socket} = SelectIdentifier.update(props, %Phoenix.LiveView.Socket{})
      socket
    end

    test "lists and counts only what the account may read", c do
      Brando.Repo.update!(Ecto.Changeset.change(c.identifier, url: "/secret"))

      as(insert_user(permissions: ~w(brando.admin.access brando.images.read)))
      socket = picker()
      assert socket.assigns.identifiers == []
      assert socket.assigns.schema_counts == %{}
      assert socket.assigns.available_schemas == []

      as(insert_user(permissions: ["brando.admin.access" | @page_read]))
      socket = picker()
      assert Enum.map(socket.assigns.identifiers, & &1.id) == [c.identifier.id]
      assert socket.assigns.schema_counts == %{Page => 1}
    end

    test "a crafted id changes nothing", c do
      Brando.Repo.update!(Ecto.Changeset.change(c.identifier, url: "/secret"))
      as(insert_user(permissions: ~w(brando.admin.access brando.images.read)))
      test = self()
      socket = picker(%{on_change: &send(test, {:selected, &1})})

      {:noreply, socket} =
        SelectIdentifier.handle_event("select_identifier", %{"id" => to_string(c.identifier.id)}, socket)

      assert socket.assigns.selected_identifier == nil
      assert socket.assigns.selected_identifier_id == nil
      assert socket.assigns.selected_creator == nil
      refute_received {:selected, _}
    end

    test "a stored selection it may not read keeps its id, without its entry", c do
      Brando.Repo.update!(Ecto.Changeset.change(c.identifier, url: "/secret"))
      as(insert_user(permissions: ~w(brando.admin.access brando.images.read)))

      socket = picker(%{selected_identifier_id: c.identifier.id})
      assert socket.assigns.selected_identifier_id == c.identifier.id
      assert socket.assigns.selected_identifier == nil
      assert socket.assigns.selected_creator == nil

      html = socket.assigns |> Map.put(:details, []) |> Map.put(:myself, %Phoenix.LiveComponent.CID{cid: 1})
      html = html |> SelectIdentifier.render() |> rendered_to_string()
      refute html =~ @secret
      refute html =~ "/secret"
    end

    test "a selection the account may read shows as before, with its creator", c do
      creator = insert_user(name: "Creator Name")
      Repo.update!(Ecto.Changeset.change(c.page, creator_id: creator.id))
      Repo.update!(Ecto.Changeset.change(c.identifier, url: "/secret"))
      as(insert_user(permissions: ["brando.admin.access" | @page_read]))

      socket = picker(%{selected_identifier_id: c.identifier.id})
      assert socket.assigns.selected_identifier.id == c.identifier.id
      assert socket.assigns.selected_creator.id == creator.id
    end

    test "reopening on another selection shows that one", c do
      creator = insert_user(name: "Creator Name")
      other = secret_page("Other page")
      Repo.update!(Ecto.Changeset.change(other, creator_id: creator.id))
      {:ok, other_identifier} = Brando.Content.create_identifier(Page, other)
      as(insert_user(permissions: ["brando.admin.access" | @page_read]))

      socket = picker(%{selected_identifier_id: c.identifier.id})
      assert socket.assigns.selected_identifier.id == c.identifier.id

      props = %{id: "picker", layout: :workspace, require_url: true, wanted_schemas: [Page]}
      {:ok, socket} = SelectIdentifier.update(Map.put(props, :selected_identifier_id, other_identifier.id), socket)

      assert socket.assigns.selected_identifier_id == other_identifier.id
      assert socket.assigns.selected_identifier.id == other_identifier.id
      assert socket.assigns.selected_creator.id == creator.id

      {:ok, socket} = SelectIdentifier.update(Map.put(props, :selected_identifier_id, nil), socket)
      assert socket.assigns.selected_identifier == nil
      assert socket.assigns.selected_creator == nil
    end

    test "an unreadable selection is not read again on each update", c do
      as(insert_user(permissions: ~w(brando.admin.access brando.images.read)))
      socket = picker(%{selected_identifier_id: c.identifier.id})

      props = %{
        id: "picker",
        layout: :workspace,
        require_url: true,
        wanted_schemas: [Page],
        selected_identifier_id: c.identifier.id
      }

      assert queries(fn -> {:ok, _} = SelectIdentifier.update(props, socket) end) == 0
    end

    test "a selection made in the picker survives the update that echoes it", c do
      Repo.update!(Ecto.Changeset.change(c.identifier, url: "/secret"))
      as(insert_user(permissions: ["brando.admin.access" | @page_read]))
      socket = picker()

      {:noreply, socket} = SelectIdentifier.handle_event("select_identifier", %{"id" => c.identifier.id}, socket)
      assert socket.assigns.selected_identifier.id == c.identifier.id

      props = %{
        id: "picker",
        layout: :workspace,
        require_url: true,
        wanted_schemas: [Page],
        selected_identifier_id: c.identifier.id
      }

      assert queries(fn -> {:ok, _} = SelectIdentifier.update(props, socket) end) == 0
    end

    test "the rich text dialog treats an unreadable destination as unavailable, keeping the saved address", c do
      Brando.Repo.update!(Ecto.Changeset.change(c.identifier, url: "/secret"))
      as(insert_user(permissions: ~w(brando.admin.access brando.images.read)))

      {:ok, socket} = TipTapLinkDialog.mount(%Phoenix.LiveView.Socket{})
      open = %{event: :open, current_identifier_id: c.identifier.id, current_href: "/saved-address"}
      {:ok, socket} = TipTapLinkDialog.update(open, socket)

      assert socket.assigns.selected_identifier == nil
      assert socket.assigns.unavailable_destination
      assert socket.assigns.draft["url"] == "/saved-address"
      refute socket.assigns.selected_identifier_id

      # Applying it unchanged keeps the stored destination on the link
      {:noreply, _} = TipTapLinkDialog.handle_event("confirm_link", %{"link" => %{"url" => "/saved-address"}}, socket)
      assert_received {:tiptap_set_link, _, %{identifier_id: id}}
      assert id == c.identifier.id

      # A new address is a new destination
      {:noreply, _} = TipTapLinkDialog.handle_event("confirm_link", %{"link" => %{"url" => "/elsewhere"}}, socket)
      assert_received {:tiptap_set_link, _, %{identifier_id: nil}}
    end

    for mode <- [:groups, :legacy] do
      @mode mode
      test "in #{mode} mode the rich text dialog drops a destination that has no URL, or is gone", c do
        put_test_env(:authorization_mode, @mode)
        Repo.update!(Ecto.Changeset.change(c.identifier, url: nil, external_url: nil))
        if @mode == :groups, do: as(insert_user(permissions: ["brando.admin.access" | @page_read]))

        for id <- [c.identifier.id, -1] do
          {:ok, socket} = TipTapLinkDialog.mount(%Phoenix.LiveView.Socket{})
          open = %{event: :open, current_identifier_id: id, current_href: "/saved-address"}
          {:ok, socket} = TipTapLinkDialog.update(open, socket)
          assert socket.assigns.unavailable_destination

          {:noreply, _} = TipTapLinkDialog.handle_event("confirm_link", %{"link" => %{"url" => "/saved-address"}}, socket)
          assert_received {:tiptap_set_link, _, %{identifier_id: nil}}
        end
      end
    end

    test "legacy mode lists everything", c do
      put_test_env(:authorization_mode, :legacy)
      Brando.Repo.update!(Ecto.Changeset.change(c.identifier, url: "/secret"))
      assert Enum.map(picker().assigns.identifiers, & &1.id) == [c.identifier.id]
    end
  end

  describe "where an asset is used" do
    setup c do
      image = Factory.insert(:image)
      show(c.page, image)
      %{image: image}
    end

    test "names what the account may read, and counts the rest", c do
      as(insert_user(permissions: ~w(brando.admin.access brando.images.read)))
      assert %{hidden: 1} = Usage.list(:image, [c.image.id])[c.image.id] |> Enum.find(&Map.has_key?(&1, :hidden))
      refute inspect(Usage.list(:image, [c.image.id])) =~ @secret

      as(insert_user(permissions: ["brando.admin.access" | @page_read]))
      assert [%{label: @secret}] = Usage.list(:image, [c.image.id])[c.image.id]
    end

    test "names what is readable beside what is not", c do
      readable = Factory.insert(:video, title: "Readable video", thumbnail_id: c.image.id)
      as(insert_user(permissions: ~w(brando.admin.access brando.images.read brando.videos.read)))

      assert [%{label: "Readable video", url: url}, %{hidden: 1}] = Usage.list(:image, [c.image.id])[c.image.id]
      assert url =~ "#{readable.id}"
    end

    test "a schema without an identifier row is not named either", c do
      Factory.insert(:video, title: "Secret video title", thumbnail_id: c.image.id)
      as(insert_user(permissions: ~w(brando.admin.access brando.images.read)))

      refute inspect(Usage.list(:image, [c.image.id])) =~ "Secret video title"
      assert [%{hidden: 2}] = Usage.list(:image, [c.image.id])[c.image.id]
    end

    test "an asset used only where the account cannot see still counts as used", c do
      as(insert_user(permissions: ~w(brando.admin.access brando.images.read)))

      assert c.image.id in Usage.used_ids(:image)
      assert Usage.labels([{Page, c.page.id}])[{Page, c.page.id}].label == @secret
      assert Usage.owners(:image, [c.image.id]) == %{c.image.id => [{Page, c.page.id}]}
    end

    test "legacy mode names every entry", c do
      put_test_env(:authorization_mode, :legacy)
      assert [%{label: @secret}] = Usage.list(:image, [c.image.id])[c.image.id]
    end

    test "the query count does not grow with the assets or the entries", c do
      as(insert_user(permissions: ["brando.admin.access" | @page_read]))

      images =
        for n <- 1..20 do
          image = Factory.insert(:image)
          show(secret_page("Page #{n}"), image)
          image.id
        end

      few = queries(fn -> Usage.list(:image, [c.image.id | Enum.take(images, 2)]) end)
      many = queries(fn -> Usage.list(:image, images) end)
      assert many == few, "#{few} queries for three assets, #{many} for twenty"
    end

    test "the listing and the form hide the name from a reader, and show it to one who may", %{conn: conn} = c do
      filed = Factory.insert(:image, status: :processed, path: "images/scopes/a.jpg", folder_id: nil)
      show(c.page, filed)
      listing = "/admin/assets/images?filter:path=images/scopes"

      {reader, _} = log_in_as(conn, permissions: ~w(brando.images.read))
      {:ok, view, html} = live(reader, listing)
      refute html =~ @secret
      assert has_element?(view, ".usage-inline .usage-hidden")

      {editor, _} = log_in_as(Phoenix.ConnTest.build_conn(), permissions: ~w(brando.images.read brando.images.update))
      {:ok, view, _html} = live(editor, Image.__admin_route__(:update, [c.image.id]))
      refute render(view) =~ @secret
      assert has_element?(view, ".usage-list .usage-hidden")

      {allowed, _} =
        log_in_as(Phoenix.ConnTest.build_conn(),
          permissions: ~w(brando.images.read brando.images.update brando.pages.read)
        )

      {:ok, view, _html} = live(allowed, Image.__admin_route__(:update, [c.image.id]))
      assert render(view) =~ @secret
      refute has_element?(view, ".usage-list .usage-hidden")

      {page_reader, _} = log_in_as(Phoenix.ConnTest.build_conn(), permissions: ~w(brando.images.read brando.pages.read))
      {:ok, view, _html} = live(page_reader, listing)
      assert render(view) =~ @secret
      refute has_element?(view, ".usage-inline .usage-hidden")
    end

    test "the delete dialog says how many places, without naming them", c do
      as(insert_user(permissions: ~w(brando.admin.access brando.images.read)))
      %{html: html} = DeleteDescription.describe(Image, c.image)
      refute html =~ @secret
      refute html =~ "<a "

      as(insert_user(permissions: ["brando.admin.access" | @page_read]))
      assert DeleteDescription.describe(Image, c.image).html =~ @secret
    end

    test "a gallery in an unreadable page is not named after it", c do
      gallery = Factory.insert(:gallery)
      source = "Elixir.Brando.Pages.Page.Blocks"
      block = Repo.insert!(%Block{type: :module, source: source, uid: Brando.Utils.generate_uid()})
      Repo.insert!(%Page.Blocks{entry_id: c.page.id, block_id: block.id, sequence: 0})
      Factory.insert(:ref, block_id: block.id, gallery_id: gallery.id)

      as(insert_user(permissions: ~w(brando.admin.access brando.galleries.read)))
      [entry] = Usage.put([gallery], :gallery)
      refute inspect(entry.usage) =~ @secret
      assert [%{hidden: 1}] = entry.usage
    end

    test "sort by use previews an unreadable entry unnamed, and still moves its assets", %{conn: conn} = c do
      folder_id = FolderBrowser.folder_id_for("images/site/default")
      Repo.update!(Ecto.Changeset.change(c.image, folder_id: folder_id))

      {conn, _user} = log_in_as(conn, permissions: ~w(brando.images.read brando.images.update))
      {:ok, view, _html} = live(conn, "/admin/assets/images?filter:folder_id=#{folder_id}")
      view |> element("button[phx-click=sweep_open]") |> render_click()
      html = view |> element("#image-sweep-form") |> render()
      refute html =~ @secret
      refute html =~ "secret-page-marker"

      view |> form("#image-sweep-form") |> render_submit()
      refute Repo.get!(Image, c.image.id).folder_id == folder_id

      Repo.update!(Ecto.Changeset.change(Repo.get!(Image, c.image.id), folder_id: folder_id))
      as(insert_user(permissions: ~w(brando.admin.access brando.images.read brando.images.update brando.pages.read)))
      assert {:ok, %{groups: [%{label: @secret, hidden: false, key: key}]}} = Sweep.plan(folder_id)
      assert key =~ "secret-page-marker"
    end
  end

  describe "the block audit" do
    test "names the entry a version holds a block for only to who may read it", %{conn: conn} = c do
      source = "Elixir.Brando.Pages.Page.Blocks"
      held = Repo.insert!(%Block{type: :module, source: source, uid: Brando.Utils.generate_uid()})
      join = Repo.insert!(%Page.Blocks{entry_id: c.page.id, block_id: held.id, sequence: 0})
      page = Repo.preload(Repo.get!(Page, c.page.id), Brando.Blueprint.preloads_for(Page))
      {:ok, _} = Brando.Revisions.create_revision(page, insert_user(role: :superuser), false)
      Repo.delete!(join)

      {reader, _} = log_in_as(conn, permissions: ~w(brando.utilities.read))
      {:ok, view, _html} = live(reader, "/admin/config/utils/loose-blocks")
      assert has_element?(view, ".block-audit-held")
      refute render(view) =~ @secret

      {allowed, _} = log_in_as(Phoenix.ConnTest.build_conn(), permissions: ["brando.utilities.read" | @page_read])
      {:ok, view, _html} = live(allowed, "/admin/config/utils/loose-blocks")
      assert render(view) =~ @secret
    end
  end

  describe "a form's usage" do
    test "counts each entry once across the form's languages, and names none it may not read", c do
      forms =
        for language <- [:en, :no] do
          Repo.insert!(%Brando.Forms.Form{key: "contact", title: "Contact", language: language})
        end

      source = "Elixir.Brando.Pages.Page.Blocks"

      for form <- forms do
        block = Repo.insert!(%Block{type: :module, source: source, uid: Brando.Utils.generate_uid()})
        Repo.insert!(%Page.Blocks{entry_id: c.page.id, block_id: block.id, sequence: System.unique_integer([:positive])})
        Repo.insert!(%Brando.Content.Var{type: :form, key: "form", label: "Form", block_id: block.id, form_id: form.id})
      end

      as(insert_user(permissions: ~w(brando.admin.access brando.forms.read)))
      assert [%{hidden: 1}] = Brando.Forms.list_usage("contact")

      as(insert_user(permissions: ["brando.admin.access", "brando.forms.read" | @page_read]))
      assert [%{label: @secret}] = Brando.Forms.list_usage("contact")
    end
  end

  describe "entry_outline's lists" do
    setup c do
      user = insert_user(role: :superuser)

      {:ok, article} =
        Brando.SyncTest.create_article(
          %{title: "Readable", slug: "readable", language: "en", status: "published", creator_id: user.id},
          :system
        )

      join = Article.__schema__(:association, :related_entries).related
      Repo.insert!(struct(join, parent_id: article.id, identifier_id: c.identifier.id, sequence: 0))
      %{article: article, superuser: user}
    end

    defp article_reader(extra \\ []) do
      insert_user(permissions: ["brando.admin.access", "brando.assistant.use", Catalog.get(:read, Article).key | extra])
    end

    defp outline(article, user) do
      Tools.call(
        "entry_outline",
        %{"content_type" => "Brando.SyncTest.Article", "id" => article.id},
        %Context{actor: user, conversation_id: 1}
      )
    end

    test "keeps the place of an entry the actor may not read, without its title", c do
      assert {:ok, %{lists: %{"related_entries" => listed}}} = outline(c.article, article_reader())
      refute listed =~ @secret
      assert listed != ""
    end

    test "names it for an actor who may read it", c do
      assert {:ok, %{lists: %{"related_entries" => @secret}}} = outline(c.article, article_reader(@page_read))
    end

    test "the review reads its entries list with the viewer's scope", c do
      as(article_reader())
      saved = c.article |> EntryFields.preload(["related_entries"]) |> EntryFields.current("related_entries")
      refute saved =~ @secret
      refute EntryFields.display(Article, "related_entries", [{:entry, Page, c.page.id}]) =~ @secret

      as(article_reader(@page_read))
      assert EntryFields.display(Article, "related_entries", [{:entry, Page, c.page.id}]) == @secret
    end

    test "a proposal's review card does not name it to a viewer who may not read it", c do
      operation = %Brando.Content.Proposals.SetFields{
        target: {Article, c.article.id},
        fields: %{"related_entries" => [{:entry, Page, c.page.id}]}
      }

      proposal = %Brando.Content.Proposals.Proposal{
        operations: [operation],
        targets: %{{Article, c.article.id} => c.article}
      }

      as(article_reader())
      refute inspect(Brando.Content.Proposals.Review.entries(proposal)) =~ @secret

      as(article_reader(@page_read))
      assert inspect(Brando.Content.Proposals.Review.entries(proposal)) =~ @secret
    end

    test "a block is not named after a link or selection the viewer may not read", c do
      link = %Brando.Content.Var{type: :link, key: "link", label: "Link", identifier: c.identifier}
      text = %Brando.Content.Var{type: :string, key: "name", label: "Name", value: "Visible excerpt"}
      selected = %Brando.Content.BlockIdentifier{identifier_id: c.identifier.id, identifier: c.identifier}

      block = %Block{
        uid: "named",
        type: :module,
        sequence: 0,
        refs: [],
        vars: [link, text],
        block_identifiers: [selected],
        children: []
      }

      entry = %{c.article | entry_blocks: [%{block: block, sequence: 0}]}
      target = {Article, entry.id}

      proposal = %Brando.Content.Proposals.Proposal{
        operations: [
          %Brando.Content.Proposals.SetBlockSelection{target: target, block_uid: "named", identifiers: [c.identifier.id]},
          %Brando.Content.Proposals.MoveBlock{target: target, block_uid: "named", placement: :append}
        ],
        targets: %{target => entry}
      }

      as(article_reader())
      [%{changes: [selection, order]}] = Brando.Content.Proposals.Review.entries(proposal)
      assert selection.block =~ "Visible excerpt"
      refute inspect(selection) =~ @secret
      assert selection.before == ["##{c.identifier.id}"]
      assert selection.entries == ["##{c.identifier.id}"]
      assert [%{excerpt: "Visible excerpt"}] = order.items

      as(article_reader(@page_read))
      [%{changes: [selection, order]}] = Brando.Content.Proposals.Review.entries(proposal)
      assert selection.block =~ @secret
      assert selection.before == [@secret]
      assert selection.entries == [@secret]
      assert [%{excerpt: @secret}] = order.items
    end

    test "the query count of a list does not grow with its entries" do
      as(article_reader(@page_read))

      entries =
        for n <- 1..20 do
          page = secret_page("Listed #{n}")
          {:ok, _} = Brando.Content.create_identifier(Page, page)
          {:entry, Page, page.id}
        end

      few = queries(fn -> EntryFields.display(Article, "related_entries", Enum.take(entries, 3)) end)
      many = queries(fn -> EntryFields.display(Article, "related_entries", entries) end)
      assert many == few, "#{few} queries for three entries, #{many} for twenty"
      assert EntryFields.display(Article, "related_entries", Enum.take(entries, 2)) == "Listed 1, Listed 2"
    end

    test "a review card reads the viewer's permissions once", c do
      as(article_reader(@page_read))
      target = {Article, c.article.id}

      card = fn count ->
        values = Map.new(1..count, &{"link#{&1}", {:entry, Page, c.page.id}})
        operation = %Brando.Content.Proposals.SetBlockValues{target: target, block_uid: "gone", values: values}
        entry = %{c.article | entry_blocks: []}
        proposal = %Brando.Content.Proposals.Proposal{operations: [operation], targets: %{target => entry}}
        queries(fn -> Brando.Content.Proposals.Review.entries(proposal) end)
      end

      # Each value reads its entry and its identifier, and nothing about the viewer
      assert card.(6) - card.(2) == 4 * 2
    end

    test "legacy mode names it", c do
      put_test_env(:authorization_mode, :legacy)
      assert {:ok, %{lists: %{"related_entries" => @secret}}} = outline(c.article, c.superuser)
    end

    test "a join list keeps the place of a record the viewer may not read", c do
      as(article_reader())
      assert EntryFields.display(Shelf, "shelved_pages", [c.page.id]) == "##{c.page.id}"

      as(article_reader(@page_read))
      assert EntryFields.display(Shelf, "shelved_pages", [c.page.id]) == @secret
    end
  end

  describe "across sites" do
    setup do
      put_test_env(:tenancy_mode, :multi)
      Tenant.put_prefix(nil)
      alpha = site("Scopes Alpha", "scopes-alpha")
      beta = site("Scopes Beta", "scopes-beta")
      alpha_live = environment(alpha, "production")
      beta_live = environment(beta, "production")

      on_exit(fn ->
        Tenant.put_prefix(nil)
        Tenant.Cache.clear()
      end)

      %{alpha: alpha, alpha_live: alpha_live, beta: beta, beta_live: beta_live}
    end

    defp site(name, key) do
      {:ok, site} =
        Tenant.Registry.create_site(%{
          name: name,
          key: key,
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      site
    end

    defp environment(site, key) do
      {:ok, environment} = Tenant.Registry.create_environment(site, %{name: key, key: key, live: key == "production"})
      prefix = Tenant.prefix(site, environment)
      repo = Brando.RuntimeConfig.get(:repo_module)
      SQL.query!(repo, ~s(CREATE SCHEMA "#{prefix}"))
      tables = SQL.query!(repo, "SELECT tablename FROM pg_tables WHERE schemaname = 'public'").rows

      tables
      |> List.flatten()
      |> Enum.reject(&Tenant.SharedTables.member?/1)
      |> Enum.each(fn table ->
        SQL.query!(repo, ~s|CREATE TABLE "#{prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|)
        SQL.query!(repo, ~s(INSERT INTO "#{prefix}"."#{table}" SELECT * FROM public."#{table}"))
      end)

      environment
    end

    test "a grant in one site does not name entries in another", c do
      user = insert_user(role: :editor)
      owner = insert_user(role: :superuser)
      {:ok, _} = Brando.Authorization.Migration.run()
      owner_scope = Scope.site(owner, c.alpha, c.alpha_live)

      {:ok, group} =
        Brando.Authorization.Groups.create(
          owner_scope,
          %{name: "Alpha readers #{System.unique_integer([:positive])}"},
          ["brando.admin.access", "brando.pages.read", "brando.images.read"]
        )

      {:ok, :ok} = Brando.Authorization.Groups.add_member(owner_scope, group.id, user.id)

      alpha = Scope.site(user, c.alpha, c.alpha_live)
      beta = Scope.site(user, c.beta, c.beta_live)
      page = {Page, c.page.id}

      Tenant.with_prefix(alpha.prefix, fn ->
        Boundary.with_scope(alpha, fn -> assert MapSet.member?(Boundary.readable_entries([page]), page) end)
      end)

      Tenant.with_prefix(beta.prefix, fn ->
        Boundary.with_scope(beta, fn -> refute MapSet.member?(Boundary.readable_entries([page]), page) end)
      end)
    end

    defp in_scope(scope, fun), do: Tenant.with_prefix(scope.prefix, fn -> Boundary.with_scope(scope, fun) end)

    defp creator_card(page, id) do
      target = {Page, page.id}
      operation = %Brando.Content.Proposals.SetFields{target: target, fields: %{"creator_id" => id}}
      proposal = %Brando.Content.Proposals.Proposal{operations: [operation], targets: %{target => page}}
      inspect(Brando.Content.Proposals.Review.entries(proposal))
    end

    test "a superuser in a site still names a user, whose permissions have no site scope", c do
      image = Factory.insert(:image)
      owner = insert_user(name: "Avatar Owner", avatar_id: image.id)
      superuser = insert_user(role: :superuser)
      {:ok, _} = Brando.Authorization.Migration.run()
      entry = {User, owner.id}

      in_scope(Scope.site(superuser, c.alpha, c.alpha_live), fn ->
        assert MapSet.member?(Boundary.readable_entries([entry]), entry)
        refute MapSet.member?(Boundary.readable_entries([{User, -1}]), {User, -1})
        assert [%{label: label}] = Usage.list(:image, [image.id])[image.id]
        assert label =~ "#{owner.id}"
        assert creator_card(c.page, owner.id) =~ "Avatar Owner"
      end)
    end

    test "anyone else in a site does not", c do
      image = Factory.insert(:image)
      owner = insert_user(name: "Avatar Owner", avatar_id: image.id)
      superuser = insert_user(role: :superuser)
      reader = insert_user(role: :editor)
      {:ok, _} = Brando.Authorization.Migration.run()

      {:ok, group} =
        Brando.Authorization.Groups.create(
          Scope.site(superuser, c.alpha, c.alpha_live),
          %{name: "Alpha readers #{System.unique_integer([:positive])}"},
          ["brando.admin.access", "brando.pages.read", "brando.images.read"]
        )

      {:ok, :ok} =
        Brando.Authorization.Groups.add_member(Scope.site(superuser, c.alpha, c.alpha_live), group.id, reader.id)

      in_scope(Scope.site(reader, c.alpha, c.alpha_live), fn ->
        assert [%{hidden: 1}] = Usage.list(:image, [image.id])[image.id]
        refute creator_card(c.page, owner.id) =~ "Avatar Owner"
      end)
    end

    test "a superuser outside a schema's scopes still names its join list's records", c do
      superuser = insert_user(role: :superuser)
      {:ok, _} = Brando.Authorization.Migration.run()

      Tenant.with_prefix(Scope.site(superuser, c.alpha, c.alpha_live).prefix, fn ->
        Boundary.with_scope(Scope.installation(superuser), fn ->
          assert EntryFields.display(Shelf, "shelved_pages", [c.page.id, -1]) == "#{@secret}, #-1"
        end)
      end)
    end

    test "a superuser is still held to a record read policy", c do
      policed = Brando.AuthorizationTestResources.Page
      superuser = insert_user(role: :superuser)
      {:ok, _} = Brando.Authorization.Migration.run()
      entry = {policed, c.page.id}

      Tenant.with_prefix(Scope.site(superuser, c.alpha, c.alpha_live).prefix, fn ->
        Boundary.with_scope(Scope.site(superuser, c.alpha, c.alpha_live), fn ->
          refute MapSet.member?(Boundary.readable_entries([entry]), entry)
        end)

        Boundary.with_scope(Scope.installation(superuser), fn ->
          refute MapSet.member?(Boundary.readable_entries([entry]), entry)
        end)
      end)
    end
  end

  describe "the helper" do
    test "reads each schema once, under one snapshot", c do
      user = insert_user(permissions: ["brando.admin.access" | @page_read])
      as(user)
      entries = for page <- [c.page | Enum.map(1..5, fn n -> secret_page("Other #{n}") end)], do: {Page, page.id}

      readable = Boundary.readable_entries(entries)
      assert MapSet.size(readable) == length(entries)

      one = queries(fn -> Boundary.readable_entries(Enum.take(entries, 1)) end)
      all = queries(fn -> Boundary.readable_entries(entries) end)
      assert all == one
      assert Engine.can?(Scope.standalone(user), :read, Page)
    end

    test "answers per record, following the resource's read policy" do
      as(insert_user(permissions: ~w(brando.admin.access)))
      refute MapSet.member?(Boundary.readable_entries([{Page, -1}]), {Page, -1})
    end

    test "an entry of a schema that no longer exists is not readable, and does not raise" do
      as(insert_user(permissions: ["brando.admin.access"]))
      assert Boundary.readable_entries([{Gone.Blueprint, 1}]) == MapSet.new()
    end

    test "without a scope or groups, every entry is readable", c do
      entry = {Page, c.page.id}
      assert MapSet.member?(Boundary.readable_entries([entry]), entry)
    end
  end
end

defmodule BrandoAdmin.EntriesInputMaskingTest do
  # With group authorization, an `:entries` input shows a selected entry the
  # editor may not read as a masked row: no title, URL or cover. The row keeps
  # its hidden inputs, so a save keeps the link, and the editor may still move
  # or remove it, which changes only the entry they edit. The text a locked
  # input reads out with its label masks it the same way. Without group
  # authorization every selected entry is named, as before.
  use Brando.LiveCase

  import Brando.Test.Users
  import Ecto.Query, only: [from: 2]
  import Phoenix.Component, only: [sigil_H: 2]

  alias Brando.Authorization.Catalog
  alias Brando.Pages.Page
  alias Brando.SyncTest
  alias Brando.SyncTest.Article

  @form "#article_form_form"
  @secret "Secret page marker"
  @listed "Listed page marker"
  @masked "An entry you can't view"
  @owned "Owned page marker"

  setup do
    put_test_env(:tenancy_mode, :none)
    secret = page_identifier(@secret)
    listed = article_identifier(@listed)

    {:ok, article} =
      SyncTest.create_article(%{title: "Linked", slug: "linked", language: "en", status: "draft"}, :system)

    join = Article.__schema__(:association, :related_entries).related
    Repo.insert!(struct(join, parent_id: article.id, identifier_id: secret.id, sequence: 0))
    Repo.insert!(struct(join, parent_id: article.id, identifier_id: listed.id, sequence: 1))

    {:ok, article: article, secret: secret, listed: listed, join: join}
  end

  defp page_identifier(title) do
    page =
      Factory.insert(:page, title: title, uri: "#{Brando.Utils.slugify(title)}-#{System.unique_integer([:positive])}")

    {:ok, identifier} = Brando.Content.create_identifier(Page, page)
    identifier
  end

  defp article_identifier(title) do
    slug = "listed-#{System.unique_integer([:positive])}"
    {:ok, article} = SyncTest.create_article(%{title: title, slug: slug, language: "en", status: "draft"}, :system)

    case Brando.Content.get_identifier(Article, article) do
      {:ok, identifier} -> identifier
      _ -> elem(Brando.Content.create_identifier(Article, article), 1)
    end
  end

  # May edit articles, may not read pages
  defp article_editor(conn) do
    put_test_env(:authorization_mode, :groups)
    keys = for action <- [:read, :update], do: Catalog.get(action, Article).key
    {conn, _user} = log_in_as(conn, permissions: ["brando.admin.access" | keys])
    conn
  end

  defp open(conn, article, form \\ "entries") do
    tab = %{"brando_tab" => "entries", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}

    {view, _} =
      conn |> put_connect_params(tab) |> live_form("/admin/articles/update/#{article.id}/#{form}", "article_form")

    await_editing_tab(view)
    view
  end

  defp await_editing_tab(view, tries \\ 100) do
    cond do
      form_assigns(view).tab_editing? -> :ok
      tries == 0 -> flunk("the tab never came to edit")
      true -> Process.sleep(20) && await_editing_tab(view, tries - 1)
    end
  end

  defp form_assigns(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == BrandoAdmin.Components.Form and &1.id == "article_form")).assigns
  end

  # The field's rows, as text
  defp field_html(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("#article_related_entries-field-wrapper .identifier-list")
    |> Floki.text()
  end

  defp params(view), do: view |> render() |> form_params(@form)

  defp change(view, params) do
    view |> element(@form) |> render_change(Map.put(params, "_target", ["article", "related_entries"]))
  end

  # "Save and continue editing": the form stays open on the saved entry
  defp stay(view), do: view |> with_target(cid_of(view, "#article_form-el")) |> render_hook("save_redirect_target", %{})

  # The first submit asks the browser for the form (`b:submit`), the second saves
  defp save(view) do
    params = params(view)
    view |> element(@form) |> render_submit(params)
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> element(@form) |> render_submit(params)
  end

  # The save runs once the blocks arrive, after the submit returns
  defp saved_title(article, title, tries \\ 100) do
    case Repo.get!(Article, article.id).title do
      ^title -> title
      other when tries == 0 -> other
      _ -> Process.sleep(20) && saved_title(article, title, tries - 1)
    end
  end

  defp saved_links(article) do
    join = Article.__schema__(:association, :related_entries).related
    Repo.all(from l in join, where: l.parent_id == ^article.id, order_by: l.sequence, select: l.identifier_id)
  end

  # As `Boundary` broadcasts after a write to groups or accounts. The view
  # takes it, and the form then draws its fields again: the first render
  # returns once the view has taken it, the next once the form has drawn.
  defp permissions_changed(view) do
    send(view.pid, {:authorization_changed, :all})
    render(view)
    render(view)
  end

  # Queries of the entries' tables (`pages`, `content_identifiers`) the view
  # runs in `fun`
  defp read_queries(view, fun) do
    pid = view.pid
    counter = :counters.new(1, [])
    id = {__MODULE__, make_ref()}

    :telemetry.attach(
      id,
      [:brando_integration, :repo, :query],
      fn _event, _measurements, meta, _config ->
        if self() == pid and meta[:source] in ["pages", "content_identifiers"], do: :counters.add(counter, 1, 1)
      end,
      nil
    )

    try do
      fun.()
      :counters.get(counter, 1)
    after
      :telemetry.detach(id)
    end
  end

  describe "with group authorization" do
    test "a selected entry the editor may not read shows without its title", %{conn: conn} = c do
      view = conn |> article_editor() |> open(c.article)
      html = field_html(view)

      refute render(view) =~ @secret
      assert html =~ @listed
      assert html =~ @masked
      # Both rows keep their ids
      assert params(view)["article"]["related_entries"] |> Map.values() |> Enum.map(& &1["identifier_id"]) ==
               [to_string(c.secret.id), to_string(c.listed.id)]
    end

    test "saving keeps the link to it", %{conn: conn} = c do
      view = conn |> article_editor() |> open(c.article)
      params = put_in(params(view), ["article", "title"], "Saved")
      change(view, params)
      save(view)

      assert saved_title(c.article, "Saved") == "Saved"
      assert saved_links(c.article) == [c.secret.id, c.listed.id]
    end

    test "the editor may move it", %{conn: conn} = c do
      view = conn |> article_editor() |> open(c.article)

      params =
        params(view)
        |> put_in(["article", "sort_related_entries_ids"], ["1", "0"])
        |> put_in(["article", "title"], "Moved")

      change(view, params)

      refute render(view) =~ @secret
      save(view)
      assert saved_title(c.article, "Moved") == "Moved"
      assert saved_links(c.article) == [c.listed.id, c.secret.id]
    end

    test "the editor may remove it", %{conn: conn} = c do
      view = conn |> article_editor() |> open(c.article)

      params =
        params(view) |> put_in(["article", "drop_related_entries_ids"], ["0"]) |> put_in(["article", "title"], "Removed")

      change(view, params)
      html = field_html(view)

      refute html =~ @masked
      assert html =~ @listed
      save(view)
      assert saved_title(c.article, "Removed") == "Removed"
      assert saved_links(c.article) == [c.listed.id]
      # The entry itself is untouched
      assert Repo.get!(Brando.Content.Identifier, c.secret.id)
    end

    test "a locked input reads it out without its title", %{conn: conn} = c do
      view = conn |> article_editor() |> open(c.article, "locked_entries")

      [value] =
        view |> render() |> Floki.parse_document!() |> Floki.find("#article_related_entries-field-wrapper .field-value")

      refute Floki.text(value) =~ @secret
      assert Floki.text(value) =~ @listed
      assert Floki.text(value) =~ @masked
    end

    test "an editor who may read the entry sees its title", %{conn: conn} = c do
      put_test_env(:authorization_mode, :groups)
      keys = for action <- [:read, :update], do: Catalog.get(action, Article).key
      {conn, _} = log_in_as(conn, permissions: ["brando.admin.access", "brando.pages.read" | keys])
      html = conn |> open(c.article) |> field_html()

      assert html =~ @secret
      refute html =~ @masked
    end

    # A change of permissions reaches the input with no edit in between
    test "losing the grant to read it masks it", %{conn: conn} = c do
      put_test_env(:authorization_mode, :groups)
      keys = for action <- [:read, :update], do: Catalog.get(action, Article).key
      {conn, _} = log_in_as(conn, permissions: ["brando.admin.access", "brando.pages.read" | keys])
      view = open(conn, c.article)
      assert field_html(view) =~ @secret
      # The picker lists it too
      view |> element("#article_related_entries-select-entries button", "Pages") |> render_click()
      assert view |> element("#article_related_entries-entries-options") |> render() =~ @secret

      # As `Groups` does on a change: the view reloads its grants
      Repo.delete_all(from g in Brando.Authorization.Grant, where: g.permission_key == "brando.pages.read")
      permissions_changed(view)

      refute render(view) =~ @secret
      assert field_html(view) =~ @masked
    end

    # What the input decided is kept between edits
    test "an edit reads none of the entries again", %{conn: conn} = c do
      view = conn |> article_editor() |> open(c.article)
      view |> element("#article_related_entries-select-entries button", "Pages") |> render_click()

      assert read_queries(view, fn ->
               change(view, put_in(params(view), ["article", "title"], "Typed"))
               render(view)
             end) == 0
    end
  end

  # The grants alone don't tell what may be read: a record read policy
  # (`Brando.AuthorizationTestPolicy`: the owner reads the entry) can decide
  # otherwise with the same grants. A form that reads its entry again, and
  # a change of permissions, check the rows and the picker's list again.
  describe "with a record read policy" do
    setup %{conn: conn} = c do
      put_test_env(:authorization_mode, :groups)
      keys = for action <- [:read, :update], do: Catalog.get(action, Article).key
      {conn, editor} = log_in_as(conn, permissions: ["authorization.policy_pages.read" | keys])
      other = insert_user()
      page = Factory.insert(:page, title: @owned, uri: "owned-#{System.unique_integer([:positive])}", creator: other)

      identifier =
        Repo.insert!(%Brando.Content.Identifier{
          schema: Brando.AuthorizationTestResources.Page,
          entry_id: page.id,
          title: @owned,
          language: :en
        })

      Repo.insert!(struct(c.join, parent_id: c.article.id, identifier_id: identifier.id, sequence: 2))
      {:ok, conn: conn, editor: editor, other: other, page: page, identifier: identifier}
    end

    defp own(page, user), do: Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [creator_id: user.id])

    test "an entry handed to the editor is named after a save in place", %{conn: conn} = c do
      view = open(conn, c.article, "policy_entries")
      refute render(view) =~ @owned

      own(c.page, c.editor)
      change(view, put_in(params(view), ["article", "title"], "Handed"))
      stay(view)
      save(view)
      assert saved_title(c.article, "Handed") == "Handed"

      assert field_html(view) =~ @owned
    end

    test "an entry taken from the editor is masked after a save in place", %{conn: conn} = c do
      own(c.page, c.editor)
      view = open(conn, c.article, "policy_entries")
      assert field_html(view) =~ @owned

      own(c.page, c.other)
      change(view, put_in(params(view), ["article", "title"], "Taken"))
      stay(view)
      save(view)
      assert saved_title(c.article, "Taken") == "Taken"

      refute render(view) =~ @owned
    end

    test "an entry handed to the editor is named once another editor's save is taken", %{conn: conn} = c do
      view = open(conn, c.article, "policy_entries")
      refute render(view) =~ @owned

      own(c.page, c.editor)
      Repo.update_all(from(a in Article, where: a.id == ^c.article.id), set: [title: "Saved elsewhere"])
      Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form, id: "article_form", event: "take_saved_entry")

      assert field_html(view) =~ @owned
    end

    test "an entry handed to the editor is named after the form reads its entry again", %{conn: conn} = c do
      view = open(conn, c.article, "policy_entries")
      refute render(view) =~ @owned

      own(c.page, c.editor)
      Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form, id: "article_form", action: :refresh_entry)

      assert field_html(view) =~ @owned
    end

    test "an entry taken from the editor is masked when a recovery copy is restored", %{conn: conn} = c do
      own(c.page, c.editor)
      view = open(conn, c.article, "policy_entries")
      assert field_html(view) =~ @owned
      form_cid = cid_of(view, "#article_form-el")
      main = params(view) |> put_in(["article", "title"], "Restored") |> Plug.Conn.Query.encode()

      view
      |> with_target(form_cid)
      |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 1, "request_id" => 1})

      copy =
        Repo.one!(
          from d in Brando.Drafts.EntryDraft,
            where: d.entry_id == ^c.article.id and is_nil(d.resolved_at),
            order_by: [desc: d.id],
            limit: 1
        )

      own(c.page, c.other)
      view |> with_target(form_cid) |> render_hook("draft_restore", %{"id" => copy.id})

      assert params(view)["article"]["title"] == "Restored"
      refute render(view) =~ @owned
      assert field_html(view) =~ @masked
    end

    # As `Boundary` broadcasts after an account is written, with no edit after
    test "an entry taken from the editor is masked once permissions change", %{conn: conn} = c do
      own(c.page, c.editor)
      view = open(conn, c.article, "policy_entries")
      assert field_html(view) =~ @owned

      own(c.page, c.other)
      permissions_changed(view)

      refute render(view) =~ @owned
      assert field_html(view) =~ @masked
    end

    test "a change of permissions that leaves the grants lists the picker again", %{conn: conn} = c do
      Repo.delete_all(from l in c.join, where: l.identifier_id == ^c.identifier.id)
      own(c.page, c.editor)
      view = open(conn, c.article, "policy_entries")
      options = "#article_related_entries-entries-options"
      assert view |> element(options) |> render() =~ @owned

      own(c.page, c.other)
      permissions_changed(view)

      refute view |> element(options) |> render() =~ @owned
    end

    # Picked from the list shown before the change, with no edit between
    test "a pick from the picker's list before a change of permissions is checked", %{conn: conn} = c do
      Repo.delete_all(from l in c.join, where: l.identifier_id == ^c.identifier.id)
      own(c.page, c.editor)
      view = open(conn, c.article, "policy_entries")
      options = "#article_related_entries-entries-options"
      picker = cid_of(view, options)
      assert view |> element(options) |> render() =~ @owned

      own(c.page, c.other)
      send(view.pid, {:authorization_changed, :all})
      view |> with_target(picker) |> render_hook("select_identifier", %{"id" => c.identifier.id})

      refute Enum.any?(params(view)["article"]["related_entries"] || %{}, fn {_, row} ->
               row["identifier_id"] == to_string(c.identifier.id)
             end)
    end
  end

  # A row whose entry no list holds (one the editor may not read, added by
  # another editor or recovered) renders masked, with its inputs.
  test "a row with no readable identifier renders masked", c do
    row = c.join |> struct(identifier_id: c.secret.id) |> Ecto.Changeset.change()

    form =
      %Article{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:related_entries, [row])
      |> Phoenix.Component.to_form()

    [field] = Phoenix.HTML.FormData.to_form(form.source, form, :related_entries, [])
    assigns = %{field: field}

    html =
      rendered_to_string(~H"""
      <BrandoAdmin.Components.Form.Input.Entries.assoc_identifier assoc_identifier={@field} available_identifiers={[]} />
      """)

    assert html =~ ~s(value="#{c.secret.id}")
    assert html =~ "masked"
    refute html =~ @secret
  end

  describe "without group authorization" do
    test "every selected entry is named", %{conn: conn} = c do
      put_test_env(:authorization_mode, :legacy)
      view = open(conn, c.article)
      html = field_html(view)

      assert html =~ @secret
      assert html =~ @listed
      refute html =~ @masked

      [value] =
        view |> render() |> Floki.parse_document!() |> Floki.find("#article_related_entries-field-wrapper .field-value")

      assert Floki.text(value) =~ @secret
    end

    # Nothing it shows depends on what may be read: a change of permissions
    # (any account written, a language switched) reads none of it again
    test "a change of permissions reads none of the entries again", %{conn: conn} = c do
      put_test_env(:authorization_mode, :legacy)
      view = open(conn, c.article)
      view |> element("#article_related_entries-select-entries button", "Pages") |> render_click()

      assert read_queries(view, fn ->
               permissions_changed(view)
               change(view, put_in(params(view), ["article", "title"], "Typed"))
               render(view)
             end) == 0
    end
  end
end

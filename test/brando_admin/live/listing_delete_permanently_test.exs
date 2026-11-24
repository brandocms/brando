defmodule BrandoAdmin.ListingDeletePermanentlyTest.StepUpListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Pages.Page, step_up: ~w(delete_entry)

  def render(assigns), do: ~H""
end

defmodule BrandoAdmin.ListingDeletePermanentlyTest do
  # Delete permanently in a listing's trash (#3927): the row as the menu
  # showed it, still in the trash, deleted for good with what the scheduled
  # purge deletes, for someone who may delete it. A refused or failed delete
  # shows the error toast.
  # Not async: the refusal test adds a foreign key to a shared table.
  use Brando.LiveCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Activity
  alias Brando.Authorization.{Groups, Migration, Scope}
  alias Brando.Notes.Note
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Revisions.Revision
  alias Brando.Translations
  alias BrandoIntegration.Repo

  setup %{current_user: user} do
    Brando.endpoint().subscribe("user:#{user.id}")
    page = trashed_page(user, "Old page")
    %{page: page}
  end

  defp trashed_page(user, title, attrs \\ %{}) do
    {:ok, page} =
      Pages.create_page(
        Map.merge(
          %{language: "en", template: "default.html", title: title, uri: Brando.Utils.slugify(title), status: :draft},
          attrs
        ),
        user
      )

    {:ok, _} = Pages.delete_page(page.id, user)
    Repo.get!(Page, page.id)
  end

  defp trash_view(conn), do: live(conn, "/admin/pages?status=deleted") |> then(fn {:ok, view, _} -> view end)

  defp delete_permanently(view, page, deleted_at \\ nil) do
    render_click(view, "delete_entry_permanently", %{
      "id" => to_string(page.id),
      "deleted_at" => DateTime.to_iso8601(deleted_at || page.deleted_at)
    })
  end

  # The toast the listing sent the user: its text and level
  defp toast do
    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: message} = payload}
    {message, payload[:level]}
  end

  defp revisions?(page),
    do: Repo.exists?(from r in Revision, where: r.entry_type == ^to_string(Page) and r.entry_id == ^page.id)

  defp notes?(page), do: Repo.exists?(from n in Note, where: n.entry_type == ^to_string(Page) and n.entry_id == ^page.id)

  # Something the purge does not clear: a project that names the page, by a
  # foreign key on the projects table
  defp refer_to(page) do
    Repo.query!("ALTER TABLE projects ADD COLUMN purge_test_page_id bigint REFERENCES pages(id)")

    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO projects (title, slug, language, purge_test_page_id, inserted_at, updated_at) " <>
          "VALUES ('Project', 'project', 'en', $1, now(), now()) RETURNING id",
        [page.id]
      )

    id
  end

  defp deleted_events(page) do
    Repo.all(
      from e in Activity.Event, where: e.schema == ^to_string(Page) and e.entry_id == ^page.id and e.action == :deleted
    )
  end

  describe "the trash's row menu" do
    test "offers Delete permanently, asking first, and no Delete", %{conn: conn, page: page} do
      view = trash_view(conn)

      assert has_element?(
               view,
               "#action_default_delete_entry_permanently_#{page.id}[phx-hook='Brando.ConfirmClick'][phx-confirm-click-destructive]"
             )

      refute has_element?(view, "#action_default_delete_entry_#{page.id}")
    end

    test "a live row has Delete and no Delete permanently", %{conn: conn, current_user: user} do
      {:ok, live_page} =
        Pages.create_page(%{language: "en", template: "default.html", title: "Live", uri: "live", status: :draft}, user)

      {:ok, view, _html} = live(conn, "/admin/pages")

      assert has_element?(view, "#action_default_delete_entry_#{live_page.id}")
      refute has_element?(view, "#action_default_delete_entry_permanently_#{live_page.id}")
    end
  end

  describe "Delete permanently" do
    test "deletes the entry with its revisions and notes, and records who did", c do
      {:ok, page} =
        Pages.create_page(
          %{language: "en", template: "default.html", title: "Noted", uri: "noted", status: :draft},
          c.current_user
        )

      {:ok, _note, _} = Brando.Notes.create_thread(Page, page.id, c.current_user, %{"body" => "Check this"})
      {:ok, _} = Pages.delete_page(page.id, c.current_user)
      page = Repo.get!(Page, page.id)
      assert revisions?(page)
      assert notes?(page)

      view = trash_view(c.conn)
      delete_permanently(view, page)

      assert {_message, :success} = toast()
      refute Repo.get(Page, page.id)
      refute revisions?(page)
      refute notes?(page)
      assert [%{user_id: user_id, details: %{"purged" => true}}] = deleted_events(page)
      assert user_id == c.current_user.id
      refute has_element?(view, "#action_default_delete_entry_permanently_#{page.id}")
    end

    test "sent twice, deletes once and records one line, and the second is refused", c do
      view = trash_view(c.conn)
      delete_permanently(view, c.page)
      delete_permanently(view, c.page)

      assert {_message, :success} = toast()
      assert {_message, :error} = toast()
      assert [_one] = deleted_events(c.page)
    end

    test "deletes nothing when the entry was restored, or restored and trashed again since", c do
      view = trash_view(c.conn)
      shown = c.page.deleted_at

      {:ok, restored} = Brando.Authorization.Boundary.restore(c.current_user, c.page)
      delete_permanently(view, c.page, shown)
      assert {_message, :error} = toast()
      assert Repo.get!(Page, c.page.id)

      Repo.update_all(from(p in Page, where: p.id == ^restored.id),
        set: [deleted_at: DateTime.add(shown, 60, :second)]
      )

      delete_permanently(view, c.page, shown)
      assert {_message, :error} = toast()
      assert Repo.get!(Page, c.page.id).deleted_at
      assert deleted_events(c.page) == []
    end

    test "a refusal keeps the row and what it holds, and the delete works once the reference is gone", c do
      {:ok, child} =
        Pages.create_page(
          %{language: "en", template: "default.html", title: "Child", uri: "child", parent_id: c.page.id, status: :draft},
          c.current_user
        )

      project_id = refer_to(c.page)

      view = trash_view(c.conn)
      delete_permanently(view, c.page)

      # Named by the kind of record that refers to it
      assert {message, :error} = toast()

      assert Enum.any?(
               Brando.Blueprint.list_blueprints(),
               &(&1.__schema__(:source) == "projects" and
                   message =~ &1 |> Brando.Blueprint.get_plural() |> String.downcase())
             )

      assert Repo.get!(Page, c.page.id).deleted_at
      # The purge's detaching of the child was rolled back with it
      assert Repo.get!(Page, child.id).parent_id == c.page.id
      assert revisions?(c.page)
      assert deleted_events(c.page) == []

      Repo.query!("UPDATE projects SET purge_test_page_id = NULL WHERE id = $1", [project_id])
      delete_permanently(view, c.page)
      assert {_message, :success} = toast()
      refute Repo.get(Page, c.page.id)
    end

    test "deleting a trashed synchronized translation frees its source to be deleted", c do
      put_test_env(Page, translatable: [mode: :synchronized])
      source = Factory.insert(:page, title: "About", uri: "about", language: :en, creator: c.current_user)
      {:ok, target} = Translations.create_target(Page, source.id, :no, c.current_user)
      {:ok, _} = Pages.delete_page(target.id, c.current_user)
      target = Repo.get!(Page, target.id)

      view = trash_view(c.conn)
      delete_permanently(view, target)
      assert {_message, :success} = toast()
      refute Translations.get_member(Page, target.id)

      render_click(view, "delete_entry", %{"id" => to_string(source.id)})
      assert {_message, :success} = toast()
      assert Repo.get!(Page, source.id).deleted_at
    end

    test "Delete selected in the trash deletes each row, and names the ones refused", c do
      other = trashed_page(c.current_user, "Other page")
      stale = trashed_page(c.current_user, "Stale page")
      view = trash_view(c.conn)

      entries =
        for page <- [c.page, other, stale] do
          shown = if page.id == stale.id, do: DateTime.add(page.deleted_at, -60, :second), else: page.deleted_at
          %{id: page.id, deleted_at: shown}
        end

      render_click(view, "delete_selected_permanently", %{"entries" => Jason.encode!(entries)})

      assert {deleted, :success} = toast()
      assert deleted =~ "2"
      assert {refused, :error} = toast()
      assert refused =~ "Stale page"
      refute Repo.get(Page, c.page.id)
      refute Repo.get(Page, other.id)
      assert Repo.get!(Page, stale.id)
    end

    test "the trash's selection offers Delete permanently, with the row as shown", %{conn: conn, page: page} do
      view = trash_view(conn)

      [cid] = view |> render() |> Floki.parse_document!() |> Floki.attribute(".selection-clear", "phx-target")

      view
      |> with_target("[data-phx-component='#{cid}']")
      |> render_click("select_row", %{"id" => to_string(page.id), "shiftKey" => "true"})

      assert has_element?(view, "#selection-action-delete-permanently[phx-confirm-click-destructive]")
      refute has_element?(view, "#selection-action-delete")

      [push] =
        view
        |> render()
        |> Floki.parse_document!()
        |> Floki.attribute("#selection-action-delete-permanently", "phx-confirm-click")

      assert [["push", %{"value" => %{"entries" => entries}}]] = Jason.decode!(push)
      assert [%{"id" => page.id, "deleted_at" => DateTime.to_iso8601(page.deleted_at)}] == Jason.decode!(entries)
    end
  end

  describe "a refused delete of a live row" do
    test "shows the error toast", c do
      put_test_env(Page, translatable: [mode: :synchronized])
      source = Factory.insert(:page, title: "Source", uri: "source", language: :en, creator: c.current_user)
      {:ok, _target} = Translations.create_target(Page, source.id, :no, c.current_user)
      {:ok, view, _html} = live(c.conn, "/admin/pages")

      render_click(view, "delete_entry", %{"id" => to_string(source.id)})
      assert {_message, :error} = toast()

      render_click(view, "delete_selected", %{"ids" => Jason.encode!([source.id])})
      assert {_message, :error} = toast()
    end
  end

  describe "a listing with a delete of its own" do
    test "the user listing deletes no user permanently", c do
      user = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      {:ok, _} = Brando.Users.delete_user(user.id, :system)
      user = Repo.get!(Brando.Users.User, user.id)
      {:ok, view, _html} = live(c.conn, "/admin/users?status=deleted")

      render_click(view, "delete_entry_permanently", %{
        "id" => to_string(user.id),
        "deleted_at" => DateTime.to_iso8601(user.deleted_at)
      })

      assert {_message, :error} = toast()
      assert Repo.get!(Brando.Users.User, user.id)
      refute has_element?(view, "[id$='_delete_entry_permanently_#{user.id}']")
    end

    test "a listing that asks again on delete asks again on Delete permanently" do
      guarded =
        for %{id: {BrandoAdmin.Reauth, opts}} <- __MODULE__.StepUpListLive.__live__()[:lifecycle].mount,
            is_list(opts),
            event <- opts[:events],
            do: event

      assert "delete_entry_permanently" in guarded
      # A selection of one row is that row: it asks as the row menu does
      assert "delete_selected_permanently" in guarded
      refute "delete_selected" in guarded
    end
  end

  describe "with groups authorization" do
    setup %{current_user: owner} do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()
      editor = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      scope = Scope.standalone(owner)

      {:ok, group} =
        Groups.create(
          scope,
          %{name: "Page deleters"},
          ~w(brando.admin.access brando.pages.read brando.pages.update brando.pages.delete brando.pages.restore)
        )

      {:ok, readers} =
        Groups.create(scope, %{name: "Page readers"}, ~w(brando.admin.access brando.pages.read))

      {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)
      {:ok, :ok} = Groups.add_member(scope, readers.id, editor.id)
      Brando.endpoint().subscribe("user:#{editor.id}")
      editor_conn = Brando.Test.log_in_user(Brando.Test.Support.admin_conn(), editor)
      %{editor: editor, group: group, scope: scope, editor_conn: editor_conn}
    end

    test "deletes a draft, and refuses one trashed while published without the publish permission", c do
      published = trashed_page(c.current_user, "Published page", %{status: :published})
      view = trash_view(c.editor_conn)

      assert has_element?(view, "#action_default_delete_entry_permanently_#{c.page.id}")
      refute has_element?(view, "#action_default_delete_entry_permanently_#{published.id}")

      # The event sent anyway, as a stale or crafted menu would
      delete_permanently(view, published)
      assert {_message, :error} = toast()
      assert Repo.get!(Page, published.id)

      delete_permanently(view, c.page)
      assert {_message, :success} = toast()
      refute Repo.get(Page, c.page.id)
    end

    test "a refusal keeps the row in groups mode too", c do
      refer_to(c.page)

      view = trash_view(c.editor_conn)
      delete_permanently(view, c.page)

      assert {_message, :error} = toast()
      assert Repo.get!(Page, c.page.id).deleted_at
    end

    test "a refused selection names only the entries the person may read", c do
      alias Brando.SyncPolicyTest.Article

      {:ok, readers} =
        Groups.create(
          c.scope,
          %{name: "Article readers"},
          ~w(brando.admin.access authorization.policy_articles.read authorization.policy_articles.delete)
        )

      {:ok, :ok} = Groups.add_member(c.scope, readers.id, c.editor.id)

      # The policy reads the creator
      article = fn title, creator ->
        {:ok, article} =
          Brando.SyncPolicyTest.create_article(
            %{title: title, slug: Brando.Utils.slugify(title), language: "en", status: :draft},
            c.current_user
          )

        Repo.update_all(from(a in Article, where: a.id == ^article.id), set: [creator_id: creator.id])
        article
      end

      own = article.("Own article", c.editor)
      hidden = article.("Hidden article", c.current_user)
      {:ok, view, _html} = live(c.editor_conn, "/admin/policy-articles")

      # Sent anyway, with the id of an entry the editor may not read
      entries = for entry <- [own, hidden], do: %{id: entry.id, deleted_at: DateTime.to_iso8601(DateTime.utc_now())}
      render_click(view, "delete_selected_permanently", %{"entries" => Jason.encode!(entries)})

      assert {refused, :error} = toast()
      assert refused =~ "Own article"
      refute refused =~ "Hidden article"
      assert Repo.get!(Article, hidden.id)
    end

    test "a permission revoked after the confirmation opened deletes nothing", c do
      view = trash_view(c.editor_conn)
      assert has_element?(view, "#action_default_delete_entry_permanently_#{c.page.id}")

      {:ok, :ok} = Groups.remove_member(c.scope, c.group.id, c.editor.id)
      delete_permanently(view, c.page)

      assert Repo.get!(Page, c.page.id).deleted_at
    end
  end
end

defmodule BrandoAdmin.RevisionLockedFieldsTest do
  # A non-superuser's recovery copies and stored revisions hold a locked field
  # as a direct save does (`LockedFields`), in both authorization modes: a value
  # the browser put in a recovery copy reaches neither the form nor a revision,
  # and a revision whose snapshot already has another value restores everything
  # but that field. The test article's `:locked` form locks `subtitle` and
  # `year` for everyone, and `:locked_slug` its slug for anyone but a superuser.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Boundary, Migration}
  alias Brando.Revisions
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Test.Users
  alias BrandoAdmin.Components.Form

  @form "#article_form_form"
  @group ~w(brando.admin.access brando.synctest_articles.read brando.synctest_articles.update
            brando.synctest_articles.publish)

  defp editor(:legacy), do: Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})

  defp editor(:groups), do: Users.insert_user(role: :editor, permissions: @group)

  defp put_mode(:legacy), do: :ok

  defp put_mode(:groups) do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
  end

  defp article(user) do
    {:ok, article} =
      SyncTest.create_article(
        %{title: "Locked", slug: "stored-slug", subtitle: "Stored", year: 2020, language: "en", status: "published"},
        user
      )

    article
  end

  defp open(editor, article, form) do
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(editor)
    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/#{form}", "article_form")
    view
  end

  defp form_cid(view), do: cid_of(view, "#article_form-el")

  defp capture(view, edits) do
    main =
      view
      |> render()
      |> form_params(@form)
      |> update_in(["article"], &Map.merge(&1, edits))
      |> Plug.Conn.Query.encode()

    view
    |> with_target(form_cid(view))
    |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 1, "request_id" => 1})
  end

  defp latest_copy(article) do
    Repo.one!(
      from d in Brando.Drafts.EntryDraft,
        where: d.entry_id == ^article.id and is_nil(d.resolved_at),
        order_by: [desc: d.id],
        limit: 1
    )
  end

  defp restore_latest_copy(view, article),
    do: view |> with_target(form_cid(view)) |> render_hook("draft_restore", %{"id" => latest_copy(article).id})

  defp store_revision(view) do
    view |> with_target(form_cid(view)) |> render_hook("store_revision", %{})
    render(view)
  end

  defp latest_revision(article) do
    Repo.one!(
      from r in Revisions.Revision,
        where: r.entry_id == ^article.id and r.entry_type == ^to_string(Article),
        order_by: [desc: r.revision],
        limit: 1
    )
  end

  defp snapshot(article) do
    {:ok, {_revision, {number, entry}}} = Revisions.get_revision(Article, article.id, latest_revision(article).revision)
    {number, entry}
  end

  defp form_assigns(view) do
    {components, _, _} = :sys.get_state(view.pid).components

    Enum.find_value(components, fn
      {_cid, {Form, _id, assigns, _private, _prints}} -> assigns
      _ -> nil
    end)
  end

  defp source_field(view, field), do: Ecto.Changeset.get_field(form_assigns(view).form.source, field)

  defp save(view, params \\ %{}) do
    view |> form(@form) |> render_submit(%{"article" => params})
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form(@form) |> render_submit(%{"article" => params})
    assert_redirect(view, 3_000)
  end

  # A revision whose snapshot holds other values than the entry, as one
  # stored before these rules or by a superuser does
  defp revision_with_changed_values(article, superuser) do
    {:ok, revision} =
      Revisions.create_revision(
        %{article | title: "Revised", subtitle: "Crafted", year: 1999, slug: "crafted-slug"},
        superuser,
        false
      )

    revision.revision
  end

  for mode <- [:legacy, :groups] do
    describe "#{mode}:" do
      setup do
        put_mode(unquote(mode))
        superuser = Users.insert_user(role: :superuser)
        if unquote(mode) == :groups, do: {:ok, _} = Migration.run()
        %{superuser: superuser, article: article(superuser)}
      end

      test "a restored recovery copy leaves the form's locked fields as saved", %{article: article} do
        view = open(editor(unquote(mode)), article, "locked")

        capture(view, %{"title" => "Restored", "subtitle" => "Crafted", "year" => "1999"})

        assert latest_copy(article).payload["main"]["subtitle"] == "Stored"
        assert latest_copy(article).payload["main"]["year"] == 2020

        # A copy stored before this rule still holds what the browser sent
        copy = latest_copy(article)
        main = Map.merge(copy.payload["main"], %{"subtitle" => "Crafted", "year" => 1999})
        copy |> Ecto.Changeset.change(payload: %{copy.payload | "main" => main}) |> Repo.update!()

        restore_latest_copy(view, article)

        assert source_field(view, :title) == "Restored"
        assert {source_field(view, :subtitle), source_field(view, :year)} == {"Stored", 2020}
      end

      test "a restored recovery copy renders the form's locked inputs as saved", %{article: article} do
        view = open(editor(unquote(mode)), article, "locked")

        capture(view, %{"title" => "Restored"})

        # A copy stored before this rule still holds what the browser sent
        copy = latest_copy(article)
        main = Map.merge(copy.payload["main"], %{"subtitle" => "Crafted", "year" => 1999})
        copy |> Ecto.Changeset.change(payload: %{copy.payload | "main" => main}) |> Repo.update!()

        restore_latest_copy(view, article)

        rendered = view |> render() |> form_params(@form)
        assert rendered["article"]["title"] == "Restored"
        assert {rendered["article"]["subtitle"], rendered["article"]["year"]} == {"Stored", "2020"}
      end

      test "a restored recovery copy renders an empty locked input's default", %{article: article} do
        Repo.update_all(from(a in Article, where: a.id == ^article.id), set: [year: nil])
        view = open(editor(unquote(mode)), article, "locked")

        capture(view, %{"title" => "Restored"})

        copy = latest_copy(article)
        main = Map.put(copy.payload["main"], "year", 1999)
        copy |> Ecto.Changeset.change(payload: %{copy.payload | "main" => main}) |> Repo.update!()

        restore_latest_copy(view, article)

        assert (view |> render() |> form_params(@form))["article"]["year"] == "2024"
      end

      test "a recovered working copy renders them as the revision has them",
           %{article: article, superuser: superuser} do
        number = revision_with_changed_values(article, superuser)
        {_number, revision_entry} = snapshot(article)
        view = open(editor(unquote(mode)), article, "locked")

        Phoenix.LiveView.send_update(view.pid, Form,
          id: "article_form",
          action: :load_working_copy,
          revision: number,
          revision_entry: revision_entry
        )

        render(view)
        capture(view, %{})

        # A copy stored before this rule still holds what the browser sent
        copy = latest_copy(article)
        main = Map.merge(copy.payload["main"], %{"subtitle" => "Crafted", "year" => 1999})
        copy |> Ecto.Changeset.change(payload: %{copy.payload | "main" => main}) |> Repo.update!()

        restore_latest_copy(view, article)

        rendered = view |> render() |> form_params(@form)
        assert {rendered["article"]["subtitle"], rendered["article"]["year"]} == {"Stored", "2020"}
      end

      test "a revision stored after a recovery copy holds the saved values", %{article: article} do
        view = open(editor(unquote(mode)), article, "locked")

        capture(view, %{"title" => "Restored", "subtitle" => "Crafted", "year" => "1999"})
        restore_latest_copy(view, article)
        store_revision(view)

        {_number, entry} = snapshot(article)
        assert entry.title == "Restored"
        assert {entry.subtitle, entry.year} == {"Stored", 2020}
      end

      test "a working copy of a revision that holds other values saves the rest",
           %{article: article, superuser: superuser} do
        number = revision_with_changed_values(article, superuser)
        {_number, revision_entry} = snapshot(%{article | id: article.id})
        view = open(editor(unquote(mode)), article, "locked")

        Phoenix.LiveView.send_update(view.pid, Form,
          id: "article_form",
          action: :load_working_copy,
          revision: number,
          revision_entry: revision_entry
        )

        assert source_field(view, :title) == "Revised"
        save(view, %{"subtitle" => "Crafted"})

        saved = Repo.get!(Article, article.id)
        assert saved.title == "Revised"
        assert {saved.subtitle, saved.year} == {"Stored", 2020}
      end

      test "a recovered working copy holds them too", %{article: article, superuser: superuser} do
        number = revision_with_changed_values(article, superuser)
        {_number, revision_entry} = snapshot(article)
        view = open(editor(unquote(mode)), article, "locked")

        Phoenix.LiveView.send_update(view.pid, Form,
          id: "article_form",
          action: :load_working_copy,
          revision: number,
          revision_entry: revision_entry
        )

        render(view)
        capture(view, %{"subtitle" => "Crafted", "year" => "1999"})
        restore_latest_copy(view, article)

        assert source_field(view, :title) == "Revised"
        assert {source_field(view, :subtitle), source_field(view, :year)} == {"Stored", 2020}
      end
    end
  end

  # Activation in groups mode needs a schema with the trash (`:restore`), and the
  # article has none: restore_params below is what both modes share.
  describe "activating a revision" do
    setup do
      superuser = Users.insert_user(role: :superuser)
      %{superuser: superuser, article: article(superuser)}
    end

    test "activating a revision that holds other values restores the rest",
         %{article: article, superuser: superuser} do
      number = revision_with_changed_values(article, superuser)
      view = open(editor(:legacy), article, "locked")
      drawer = cid_of(view, "#article_form-revisions-drawer")

      view |> with_target(drawer) |> render_hook("activate_revision", %{"value" => number})

      saved = Repo.get!(Article, article.id)
      assert saved.title == "Revised"
      assert {saved.subtitle, saved.year} == {"Stored", 2020}
    end

    test "a slug locked unless superuser holds for an editor, and restores for a superuser",
         %{article: article, superuser: superuser} do
      number = revision_with_changed_values(article, superuser)
      view = open(editor(:legacy), article, "locked-slug")
      drawer = cid_of(view, "#article_form-revisions-drawer")

      view |> with_target(drawer) |> render_hook("activate_revision", %{"value" => number})
      assert Repo.get!(Article, article.id).slug == "stored-slug"

      assert {:ok, restored} = Revisions.set_entry_to_revision(Article, article.id, number, superuser)
      assert {restored.slug, restored.subtitle} == {"crafted-slug", "Crafted"}
    end
  end

  test "groups: restoring holds a non-superuser's locked fields, and not a superuser's" do
    put_mode(:groups)
    superuser = Users.insert_user(role: :superuser)
    {:ok, _} = Migration.run()
    article = article(superuser)
    revised = %{article | title: "Revised", subtitle: "Crafted"}
    locked = Article.__form__(:locked)

    params = Revisions.restore_params(revised, article, editor(:groups), locked)
    assert params.title == "Revised"
    refute Map.has_key?(params, :subtitle)

    assert %{subtitle: "Crafted"} = Revisions.restore_params(revised, article, superuser, locked)
  end

  test "a form restoring a revision holds what it has no input for and no form offers" do
    image = Factory.insert(:image, path: "images/a.jpg")
    open_form = %Brando.Blueprint.Forms.Form{tabs: []}
    params = Revisions.restore_params(%{image | path: "images/b.jpg", title: "New"}, image, editor(:legacy), open_form)

    assert params.title == "New"
    refute Map.has_key?(params, :path)
  end

  test "a job restoring a revision holds what no form offers" do
    superuser = Users.insert_user(role: :superuser)
    image = Factory.insert(:image, path: "images/a.jpg")

    assert %{path: "images/b.jpg", title: "New"} =
             Brando.Revisions.restore_params(%{image | path: "images/b.jpg", title: "New"}, image, superuser)

    params = Brando.Revisions.restore_params(%{image | path: "images/b.jpg", title: "New"}, image, nil)
    assert params.title == "New"
    refute Map.has_key?(params, :path)
  end
end

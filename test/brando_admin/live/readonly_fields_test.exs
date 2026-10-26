defmodule BrandoAdmin.ReadonlyFieldsTest do
  # An input declared `readonly: true` or `disabled: true` is locked for
  # everyone, superusers included: the save takes no value the browser sends
  # for it, and keeps the one the form has (the test article's `:locked`
  # form). A locked slug of a new entry is filled in from its source on the
  # server, as the browser's Slug hook would.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Blueprint.Forms
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.LockedFields

  @form "#article_form_form"

  # The first submit asks the browser for the form (`b:submit`), the second saves
  defp save(view, params) do
    view |> form(@form) |> render_submit(%{"article" => params})
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form(@form) |> render_submit(%{"article" => params})
    assert_redirect(view, 3_000)
  end

  test "a save keeps a locked field's value, whatever the params say", %{conn: conn, current_user: user} do
    {:ok, article} =
      SyncTest.create_article(
        %{title: "Locked", slug: "locked", subtitle: "Stored", year: 2020, language: "en", status: "published"},
        user
      )

    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/locked", "article_form")

    save(view, %{
      "title" => "Edited",
      "slug" => "edited",
      "subtitle" => "Crafted",
      "year" => "1999",
      "featured" => "true"
    })

    saved = Repo.get!(Article, article.id)
    assert {saved.title, saved.slug} == {"Edited", "locked"}
    assert {saved.subtitle, saved.year, saved.featured} == {"Stored", 2020, false}
  end

  # A new entry's default params are the form's, not the browser's: a locked
  # field keeps them, and an empty one takes its input's `default:`. Picking
  # an asset rebuilds the form's changeset (its changes become its data).
  test "a new entry keeps the form's values for its locked fields", %{conn: conn} do
    image = Factory.insert(:image, focal: %Brando.Images.Focal{x: 50, y: 50})
    {view, _html} = live_form(conn, "/admin/articles/create/locked", "article_form")

    Phoenix.LiveView.send_update(view.pid, Form,
      id: "article_form",
      event: "entry_field_upload_complete",
      asset_type: :image,
      field: :cover,
      path: [],
      asset: image
    )

    save(view, %{
      "title" => "New Entry",
      "slug" => "crafted",
      "subtitle" => "Crafted",
      "year" => "1999",
      "featured" => "true"
    })

    saved = Repo.get_by!(Article, title: "New Entry")
    assert {saved.subtitle, saved.year, saved.featured, saved.cover_id} == {"Set by the form", 2024, false, image.id}
    assert saved.slug == "new-entry"
  end

  describe "a slug locked for anyone but superusers" do
    setup %{current_user: user} do
      editor = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      {:ok, editor: editor, superuser: user}
    end

    # The Slug hook's value is dropped like any locked field's, so the server
    # fills it in, or the entry could not be created
    test "an editor creates an entry with the slug derived from its source", %{editor: editor} do
      conn = log_in_user(Phoenix.ConnTest.build_conn(), editor)
      {view, _html} = live_form(conn, "/admin/articles/create/locked-slug", "article_form")

      html = view |> form(@form) |> render_change(%{"article" => %{"title" => "Første sak", "slug" => "crafted"}})
      assert html =~ ~s(value="forste-sak")

      save(view, %{"title" => "Første sak", "slug" => "crafted"})

      assert Repo.get_by!(Article, title: "Første sak").slug == "forste-sak"
    end

    test "a superuser still types it", %{conn: conn} do
      {view, _html} = live_form(conn, "/admin/articles/create/locked-slug", "article_form")
      save(view, %{"title" => "Typed", "slug" => "by-hand"})

      assert Repo.get_by!(Article, title: "Typed").slug == "by-hand"
    end

    # A saved entry's slug is its URL: a lock keeps it as the title changes
    test "a saved entry's slug stays when the title changes", %{editor: editor, superuser: user} do
      {:ok, article} =
        SyncTest.create_article(%{title: "Stored", slug: "stored", language: "en", status: "published"}, user)

      conn = log_in_user(Phoenix.ConnTest.build_conn(), editor)
      {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/locked-slug", "article_form")
      save(view, %{"title" => "Renamed", "slug" => "renamed"})

      assert {Repo.get!(Article, article.id).title, Repo.get!(Article, article.id).slug} == {"Renamed", "stored"}
    end
  end

  # A recovery copy holds what the browser sent: restoring it doesn't save a
  # locked field.
  test "a restored recovery copy doesn't change a locked field", %{conn: conn, current_user: user} do
    {:ok, article} =
      SyncTest.create_article(
        %{title: "Locked", slug: "locked", subtitle: "Stored", year: 2020, language: "en", status: "published"},
        user
      )

    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/locked", "article_form")
    form_cid = cid_of(view, "#article_form-el")

    main =
      view
      |> render()
      |> form_params(@form)
      |> put_in(["article", "subtitle"], "Crafted")
      |> put_in(["article", "title"], "Restored")
      |> Plug.Conn.Query.encode()

    view
    |> with_target(form_cid)
    |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 1, "request_id" => 1})

    copy =
      Repo.one!(
        from d in Brando.Drafts.EntryDraft,
          where: d.entry_id == ^article.id and is_nil(d.resolved_at),
          order_by: [desc: d.id],
          limit: 1
      )

    view |> with_target(form_cid) |> render_hook("draft_restore", %{"id" => copy.id})
    save(view, %{})

    saved = Repo.get!(Article, article.id)
    assert {saved.title, saved.subtitle} == {"Restored", "Stored"}
  end

  # A revision's working copy is the server's: its locked values are saved
  # with the rest of it.
  test "a revision's working copy keeps its value for a locked field", %{conn: conn, current_user: user} do
    {:ok, article} =
      SyncTest.create_article(
        %{title: "Locked", slug: "locked", subtitle: "Stored", year: 2020, language: "en", status: "published"},
        user
      )

    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/locked", "article_form")

    Phoenix.LiveView.send_update(view.pid, Form,
      id: "article_form",
      action: :load_working_copy,
      revision: 1,
      revision_entry: %{article | subtitle: "From the revision", title: "Revised"}
    )

    save(view, %{"subtitle" => "Crafted"})

    saved = Repo.get!(Article, article.id)
    assert {saved.title, saved.subtitle} == {"Revised", "From the revision"}
  end

  # Another revision loaded after it replaces the first one's values
  test "a second working copy replaces the first one's locked values", %{conn: conn, current_user: user} do
    {:ok, article} =
      SyncTest.create_article(
        %{title: "Locked", slug: "locked", subtitle: "Stored", year: 2020, language: "en", status: "published"},
        user
      )

    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/locked", "article_form")

    for {revision, subtitle} <- [{1, "Older"}, {2, "Stored"}] do
      Phoenix.LiveView.send_update(view.pid, Form,
        id: "article_form",
        action: :load_working_copy,
        revision: revision,
        revision_entry: %{article | subtitle: subtitle, title: "Revision #{revision}"}
      )
    end

    save(view, %{})

    saved = Repo.get!(Article, article.id)
    assert {saved.title, saved.subtitle} == {"Revision 2", "Stored"}
  end

  # Another editor (a superuser) saves a field locked for this one: this
  # editor's next save doesn't put back the value it opened with (the form
  # records only the server's values that differ from the entry).
  test "another editor's save of a locked field stays", %{current_user: user} do
    image = Factory.insert(:image, path: "images/locked/a.jpg", status: :processed, width: 800, creator: user)
    editor = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
    conn = log_in_user(Phoenix.ConnTest.build_conn(), editor)
    {view, _html} = live_form(conn, "/admin/assets/images/update/#{image.id}", "image_form")

    Brando.Images.Image |> Repo.get!(image.id) |> Ecto.Changeset.change(width: 1200) |> Repo.update!()

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      Brando.Tenant.Topic.entry("field_sync", Brando.Images.Image, image.id),
      {:entry_saved, %{tab: "another-tab", user_id: user.id}}
    )

    render(view)
    view |> form("#image_form_form") |> render_submit(%{"image" => %{"credits" => %{"en" => "Edited"}}})
    assert_redirect(view, 3_000)

    saved = Repo.get!(Brando.Images.Image, image.id)
    assert {saved.width, saved.credits["en"]} == {1200, "Edited"}
  end

  describe "LockedFields.lock/6" do
    setup do
      input = &%Forms.Input{name: &1, type: &2, opts: &3}

      blueprint = %Forms.Form{
        tabs: [
          %Forms.Tab{
            fields: [
              %Forms.Fieldset{
                fields: [
                  input.(:title, :text, []),
                  input.(:slug, :slug, readonly: true),
                  input.(:subtitle, :text, readonly: true),
                  input.(:year, :number, disabled: true, default: fn -> 2024 end),
                  input.(:cover, :image, disabled: true)
                ]
              },
              %Forms.Fieldset{superuser: true, fields: [input.(:language, :slug, [])]}
            ]
          }
        ]
      }

      {:ok, blueprint: blueprint}
    end

    test "drops a locked field's param for everyone", %{blueprint: blueprint} do
      params = %{"title" => "T", "slug" => "s", "subtitle" => "x", "year" => "1", "cover_id" => "3"}
      entry = %Article{year: 2020}
      none = {%{}, %{}}

      assert LockedFields.lock(params, Article, blueprint, %Brando.Users.User{role: :superuser}, none, entry) ==
               %{"title" => "T"}

      # A slug in a superuser fieldset is locked for anyone else
      params = Map.put(params, "language", "x")

      assert LockedFields.lock(params, Article, blueprint, %Brando.Users.User{role: :superuser}, none, entry) ==
               %{"title" => "T", "language" => "x"}

      assert LockedFields.lock(params, Article, blueprint, %Brando.Users.User{role: :editor}, none, entry) ==
               %{"title" => "T"}
    end

    test "puts back the server's value, and a default while the entry's is empty", %{blueprint: blueprint} do
      user = %Brando.Users.User{role: :superuser}
      changeset = Ecto.Changeset.change(%Article{}, subtitle: "Set", cover_id: 7, title: "Not locked")
      values = LockedFields.server_values(changeset, Article, blueprint, user, %Article{})
      assert values == %{subtitle: "Set", cover_id: 7}
      defaults = LockedFields.defaults(Article, blueprint, user)
      assert defaults == %{year: 2024}

      assert LockedFields.lock(%{"subtitle" => "x"}, Article, blueprint, user, {values, defaults}, %Article{}) ==
               %{"subtitle" => "Set", "year" => 2024, "cover_id" => 7}

      # Once the entry has them, there is nothing to put back
      saved = %Article{subtitle: "Set", cover_id: 7, year: 2020}
      assert LockedFields.lock(%{"subtitle" => "x"}, Article, blueprint, user, {values, defaults}, saved) == %{}
    end

    test "keeps a server value that is false or nil", %{blueprint: blueprint} do
      user = %Brando.Users.User{role: :superuser}
      stored = %Article{subtitle: "Stored", year: 2024}
      changeset = Ecto.Changeset.change(stored, subtitle: nil)
      values = LockedFields.server_values(changeset, Article, blueprint, user, stored)

      assert LockedFields.lock(%{"subtitle" => "x"}, Article, blueprint, user, {values, %{}}, stored) ==
               %{"subtitle" => nil}
    end
  end

  describe "LockedFields.derive_slugs/5" do
    setup do
      editor = %Brando.Users.User{role: :editor}

      blueprint = fn opts ->
        fields = [%Forms.Input{name: :title, type: :text}, %Forms.Input{name: :slug, type: :slug, opts: opts}]
        %Forms.Form{tabs: [%Forms.Tab{fields: [%Forms.Fieldset{fields: fields}]}]}
      end

      derive = fn opts, entry, params ->
        changeset = Ecto.Changeset.cast(entry, params, [:title, :slug, :subtitle, :year])
        LockedFields.derive_slugs(params, changeset, Article, blueprint.(opts), editor)
      end

      {:ok, derive: derive, editor: editor}
    end

    test "generates an empty locked slug from its sources, as the Slug hook", %{derive: derive} do
      locked = [readonly: :unless_superuser]

      assert derive.([source: :title] ++ locked, %Article{}, %{"title" => "Hello Wörld/Foo"}) ==
               %{"title" => "Hello Wörld/Foo", "slug" => "hello-world-foo"}

      # Other punctuation goes without separating, as in the hook
      assert %{"slug" => "abc-strasse"} = derive.([source: :title] ++ locked, %Article{}, %{"title" => "a_b.c Straße"})

      assert %{"slug" => "first-2024"} =
               derive.([source: [:title, :year]] ++ locked, %Article{}, %{"title" => "First", "year" => "2024"})

      assert %{"slug" => "parent/child-page"} =
               derive.([source: :title, prefix: "parent/"] ++ locked, %Article{}, %{"title" => "Child page"})

      prefix = fn changeset -> Ecto.Changeset.get_field(changeset, :subtitle) <> "/" end

      assert %{"slug" => "from-subtitle/child"} =
               derive.([source: :title, prefix: prefix] ++ locked, %Article{}, %{
                 "title" => "Child",
                 "subtitle" => "from-subtitle"
               })

      assert %{"slug" => "primaryColorBla"} =
               derive.([source: :title, camel_case: true] ++ locked, %Article{}, %{"title" => "Primary color blå"})

      # The hook keeps the Latin-1 letters it doesn't replace
      assert %{"slug" => "straßeaeRo"} =
               derive.([source: :title, camel_case: true] ++ locked, %Article{}, %{"title" => "Straße/æ-rø!"})
    end

    # A date source is slugged as its input holds it
    test "generates a slug from a date", %{editor: editor} do
      fields = [%Forms.Input{name: :slug, type: :slug, opts: [source: [:title, :published_on], readonly: true]}]
      blueprint = %Forms.Form{tabs: [%Forms.Tab{fields: [%Forms.Fieldset{fields: fields}]}]}
      params = %{"title" => "Notes", "published_on" => "2026-10-26"}

      changeset =
        Ecto.Changeset.cast({%{}, %{title: :string, slug: :string, published_on: :date}}, params, [:title, :published_on])

      assert %{"slug" => "notes-2026-10-26"} = LockedFields.derive_slugs(params, changeset, Article, blueprint, editor)

      # A date-time as the DateTimePicker writes it, in UTC with milliseconds
      types = %{title: :string, slug: :string, published_on: :utc_datetime}
      params = %{"title" => "Notes", "published_on" => "2026-10-26T14:30:00+02:00"}
      changeset = Ecto.Changeset.cast({%{}, types}, params, [:title, :published_on])

      assert %{"slug" => "notes-2026-10-26t123000000z"} =
               LockedFields.derive_slugs(params, changeset, Article, blueprint, editor)
    end

    test "leaves a slug that has a value, one without a source, and one not locked", %{derive: derive} do
      assert derive.([source: :title, readonly: true], %Article{slug: "saved"}, %{"title" => "New"}) ==
               %{"title" => "New"}

      # No prefix without a slug
      assert derive.([source: :title, readonly: true, prefix: "parent/"], %Article{}, %{"title" => "?!"}) ==
               %{"title" => "?!"}

      assert derive.([readonly: true], %Article{}, %{"title" => "New"}) == %{"title" => "New"}
      assert derive.([source: :title], %Article{}, %{"title" => "New"}) == %{"title" => "New"}
    end

    test "leaves a slug locked only for others to a superuser", %{editor: editor} do
      fields = [%Forms.Input{name: :slug, type: :slug, opts: [source: :title, readonly: :unless_superuser]}]
      blueprint = %Forms.Form{tabs: [%Forms.Tab{fields: [%Forms.Fieldset{fields: fields}]}]}
      params = %{"title" => "New"}
      changeset = Ecto.Changeset.cast(%Article{}, params, [:title])

      assert LockedFields.derive_slugs(params, changeset, Article, blueprint, %{editor | role: :superuser}) == params

      assert LockedFields.derive_slugs(params, changeset, Article, blueprint, editor) == %{
               "title" => "New",
               "slug" => "new"
             }
    end
  end
end

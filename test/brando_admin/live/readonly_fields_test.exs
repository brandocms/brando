defmodule BrandoAdmin.ReadonlyFieldsTest do
  # An input declared `readonly: true` or `disabled: true` is locked for
  # everyone, superusers included: the save takes no value the browser sends
  # for it, and keeps the one the form has (the test article's `:locked`
  # form). A slug is filled in by the browser and stays editable.
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
    assert {saved.title, saved.slug} == {"Edited", "edited"}
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

    save(view, %{"title" => "New", "slug" => "new", "subtitle" => "Crafted", "year" => "1999", "featured" => "true"})

    saved = Repo.get_by!(Article, title: "New")
    assert {saved.subtitle, saved.year, saved.featured, saved.cover_id} == {"Set by the form", 2024, false, image.id}
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

      assert LockedFields.lock(params, Article, blueprint, %Brando.Users.User{role: :superuser}, %{}, entry) ==
               %{"title" => "T", "slug" => "s"}

      # A slug in a superuser fieldset is locked for anyone else
      assert LockedFields.lock(
               Map.put(params, "language", "x"),
               Article,
               blueprint,
               %Brando.Users.User{role: :editor},
               %{},
               entry
             ) ==
               %{"title" => "T", "slug" => "s"}
    end

    test "puts back the server's value, or an empty field's default", %{blueprint: blueprint} do
      user = %Brando.Users.User{role: :superuser}
      changeset = Ecto.Changeset.change(%Article{}, subtitle: "Set", cover_id: 7, title: "Not locked")
      values = LockedFields.server_values(changeset, Article, blueprint, user, %Article{})
      assert values == %{subtitle: "Set", cover_id: 7}

      assert LockedFields.lock(%{"subtitle" => "x"}, Article, blueprint, user, values, %Article{}) ==
               %{"subtitle" => "Set", "year" => 2024, "cover_id" => 7}

      # Once the entry has them, there is nothing to put back
      saved = %Article{subtitle: "Set", cover_id: 7, year: 2020}
      assert LockedFields.lock(%{"subtitle" => "x"}, Article, blueprint, user, values, saved) == %{}
    end
  end
end

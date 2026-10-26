defmodule BrandoAdmin.ReadonlyFieldsTest do
  # An input declared `readonly: true` or `disabled: true` is locked for
  # everyone, superusers included: the save takes no value the browser sends
  # for it, and keeps the one the form has (the test article's `:locked`
  # form). A slug is filled in by the browser and stays editable.
  use Brando.LiveCase

  alias Brando.Blueprint.Forms
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
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
    cover = Factory.insert(:image)

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
      "featured" => "true",
      "cover_id" => to_string(cover.id)
    })

    saved = Repo.get!(Article, article.id)
    assert {saved.title, saved.slug} == {"Edited", "edited"}
    assert {saved.subtitle, saved.year, saved.featured, saved.cover_id} == {"Stored", 2020, false, nil}
  end

  # A new entry's default params are the form's, not the browser's: a locked
  # field keeps them, and an empty one takes its input's `default:`.
  test "a new entry keeps the form's values for its locked fields", %{conn: conn} do
    {view, _html} = live_form(conn, "/admin/articles/create/locked", "article_form")

    save(view, %{"title" => "New", "slug" => "new", "subtitle" => "Crafted", "year" => "1999", "featured" => "true"})

    saved = Repo.get_by!(Article, title: "New")
    assert {saved.subtitle, saved.year, saved.featured} == {"Set by the form", 2024, false}
  end

  describe "LockedFields.lock/5" do
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
              }
            ]
          }
        ]
      }

      {:ok, blueprint: blueprint}
    end

    test "drops a locked field's param for everyone", %{blueprint: blueprint} do
      params = %{"title" => "T", "slug" => "s", "subtitle" => "x", "year" => "1", "cover_id" => "3"}
      current = Ecto.Changeset.change(%Article{year: 2020})

      for role <- [:superuser, :editor] do
        assert LockedFields.lock(params, Article, blueprint, %Brando.Users.User{role: role}, current) ==
                 %{"title" => "T", "slug" => "s"}
      end
    end

    test "puts back the form's change, or an empty field's default", %{blueprint: blueprint} do
      user = %Brando.Users.User{role: :superuser}
      current = Ecto.Changeset.change(%Article{}, subtitle: "Set", cover_id: 7)

      assert LockedFields.lock(%{"subtitle" => "x"}, Article, blueprint, user, current) ==
               %{"subtitle" => "Set", "year" => 2024, "cover_id" => 7}
    end
  end
end

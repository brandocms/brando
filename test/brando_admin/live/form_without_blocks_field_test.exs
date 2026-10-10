defmodule BrandoAdmin.FormWithoutBlocksFieldTest do
  # The test article's `:no_blocks` form leaves out the schema's `blocks`
  # relation. Saving used to wait forever for a block field that was never
  # mounted.
  use Brando.LiveCase

  alias Brando.SyncTest

  test "a form that omits the schema's blocks field still saves", %{conn: conn, current_user: user} do
    {:ok, article} =
      SyncTest.create_article(
        %{title: "No blocks here", slug: "no-blocks-here", language: "en", status: "published", year: 2020},
        user
      )

    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/no-blocks", "article_form")
    refute has_element?(view, "[id^='article_form-blocks-']")

    view
    |> form("#article_form_form")
    |> render_submit(%{"article" => %{"title" => "Saved without blocks"}})

    assert_push_event(view, "b:submit", %{}, 2_000)

    view
    |> form("#article_form_form")
    |> render_submit(%{"article" => %{"title" => "Saved without blocks"}})

    assert_redirect(view, 3_000)

    {:ok, saved} = SyncTest.get_article(%{matches: %{id: article.id}})
    assert saved.title == "Saved without blocks"
  end

  # Review: a schema without block fields saves through its own path,
  # which kept saying the form held a revision's working copy, so every
  # later recovery copy said so too, and none matched the saved entry.
  test "a recovery copy taken after a working copy is saved, without block fields, is not one", %{conn: conn} do
    other = Factory.insert(:random_user, config: %Brando.Users.UserConfig{}, avatar: nil)
    {view, _html} = live_form(conn, "/admin/users/update/#{other.id}", "user_form")
    form_cid = cid_of(view, "#user_form-el")

    # a revision's working copy, as the revisions drawer loads one
    Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form,
      id: "user_form",
      action: :load_working_copy,
      revision: 1,
      revision_entry: %{other | name: "From the revision"}
    )

    view |> with_target(form_cid) |> render_hook("save_redirect_target", %{})
    # no block fields: one submit saves
    view |> form("#user_form_form") |> render_submit()
    Brando.EditSessionEditors.await(fn -> Brando.Repo.get!(Brando.Users.User, other.id).name == "From the revision" end)

    view |> form("#user_form_form", %{"user" => %{"name" => "Typed after"}}) |> render_change()
    main = view |> render() |> form_params("#user_form_form") |> Plug.Conn.Query.encode()

    view
    |> with_target(form_cid)
    |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 1, "request_id" => 1})

    import Ecto.Query, only: [from: 2]
    copies = fn -> Brando.Repo.all(from(d in Brando.Drafts.EntryDraft, where: d.entry_id == ^other.id)) end
    Brando.EditSessionEditors.await(fn -> Enum.any?(copies.(), &(&1.payload["main"]["name"] == "Typed after")) end)

    copy = Enum.find(copies.(), &(&1.payload["main"]["name"] == "Typed after"))
    refute Map.has_key?(copy.payload, "working_copy")
  end
end

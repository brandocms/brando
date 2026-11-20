defmodule BrandoAdmin.TranslationReplaceTrashedTest do
  # Creating a translation in a language whose version is in the trash, from
  # the listing's row menu and the form's translation panel: the button asks
  # first, and the confirmed event deletes the version in the trash for good
  # and creates the new one (#3762). Cancelling the dialog sends nothing; the
  # E2E spec covers it. Not async: pages are made synchronized through the
  # application env.
  use Brando.LiveCase, async: false

  alias Brando.Authorization.{Groups, Migration, Scope}
  alias Brando.Pages.Page
  alias Brando.Translations
  alias BrandoIntegration.Repo

  setup %{current_user: user} do
    put_test_env(Page, translatable: [mode: :synchronized])
    # The listing shows the content language, English
    source = Factory.insert(:page, title: "About", uri: "about", language: :en, creator: user)
    {:ok, target} = Translations.create_target(Page, source.id, :no, user)
    {:ok, _} = Brando.Pages.delete_page(target.id, user)
    %{source: source, target: target}
  end

  defp replaced_by(c) do
    %{group_id: group_id} = Translations.get_member(Page, c.source.id)

    assert [%{entry_id: source_id}, %{entry_id: new_id, language: "no", role: :target}] =
             Translations.list_members(group_id)

    assert source_id == c.source.id
    refute Repo.get(Page, c.target.id)
    new_id
  end

  defp still_in_trash(c) do
    assert %{deleted_at: %DateTime{}} = Repo.get!(Page, c.target.id)
    assert %{role: :target} = Translations.get_member(Page, c.target.id)
  end

  describe "listing" do
    test "Create translation asks before replacing a version in the trash, and a free language does not",
         %{conn: conn} = c do
      alone = Factory.insert(:page, title: "Alone", uri: "alone", language: :en, creator: c.current_user)
      {:ok, view, _html} = live(conn, "/admin/pages")
      await_selector(view, ".listing-translations")

      assert has_element?(
               view,
               "[id$='_create_translation_#{c.source.id}_lang_no'][phx-hook='Brando.ConfirmClick'][phx-confirm-click-destructive]"
             )

      assert has_element?(view, "[id$='_create_translation_#{alone.id}_lang_no'][phx-click='create_entry_translation']")
      refute has_element?(view, "[id$='_create_translation_#{alone.id}_lang_no'][phx-hook='Brando.ConfirmClick']")
    end

    test "confirmed, the version in the trash is deleted and the new one opens", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, "/admin/pages")

      render_click(view, "create_entry_translation", %{
        "id" => to_string(c.source.id),
        "language" => "no",
        "replace" => "true"
      })

      new_id = replaced_by(c)
      assert_redirect(view, "/admin/pages/update/#{new_id}")
    end

    test "Create and translate, confirmed, opens the new one with Translate with AI", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, "/admin/pages")

      render_click(view, "create_entry_translation_with_ai", %{
        "id" => to_string(c.source.id),
        "language" => "no",
        "replace" => "true"
      })

      new_id = replaced_by(c)
      assert_redirect(view, "/admin/pages/update/#{new_id}?translate=ai")
    end

    test "without the confirmation, the language in the trash is refused as before", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, "/admin/pages")

      render_click(view, "create_entry_translation", %{"id" => to_string(c.source.id), "language" => "no"})

      still_in_trash(c)
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
          %{name: "Page writers"},
          ~w(brando.admin.access brando.pages.read brando.pages.update brando.pages.create brando.pages.duplicate)
        )

      {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)
      %{editor_conn: Brando.Test.log_in_user(Brando.Test.Support.admin_conn(), editor)}
    end

    test "an editor who may not delete pages is told the version is in the trash", c do
      {:ok, view, _html} = live(c.editor_conn, "/admin/pages")

      render_click(view, "create_entry_translation", %{
        "id" => to_string(c.source.id),
        "language" => "no",
        "replace" => "true"
      })

      still_in_trash(c)
    end
  end

  describe "form" do
    defp open(conn, id) do
      {view, _html} = live_form(conn, "/admin/pages/update/#{id}")
      await_selector(view, ".translation-panel.is-source")
      view
    end

    defp create_button, do: ".translation-create button[phx-value-language='no']"

    test "the panel offers the language in the trash, and asks first", %{conn: conn} = c do
      view = open(conn, c.source.id)

      assert has_element?(view, create_button() <> "[phx-hook='Brando.ConfirmClick'][phx-confirm-click-destructive]")
    end

    test "confirmed, the version in the trash is deleted and the new one opens", %{conn: conn} = c do
      view = open(conn, c.source.id)
      [cid] = view |> render() |> Floki.parse_document!() |> Floki.attribute(create_button(), "phx-target")

      view
      |> with_target("[data-phx-component='#{cid}']")
      |> render_click("create_translation", %{"language" => "no", "replace" => "true"})

      new_id = replaced_by(c)
      assert_redirect(view, "/admin/pages/update/#{new_id}")
    end

    test "without the confirmation, the language in the trash is refused", %{conn: conn} = c do
      view = open(conn, c.source.id)
      [cid] = view |> render() |> Floki.parse_document!() |> Floki.attribute(create_button(), "phx-target")

      view
      |> with_target("[data-phx-component='#{cid}']")
      |> render_click("create_translation", %{"language" => "no"})

      still_in_trash(c)
    end
  end
end

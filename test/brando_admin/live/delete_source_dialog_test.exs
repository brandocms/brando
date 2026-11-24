defmodule BrandoAdmin.DeleteSourceDialogTest do
  # Delete on the source of synchronized translations (#3926): the dialog
  # lists them and asks whether they go with it or stay, and the listing
  # deletes as it was told, against the group as the dialog showed it. A
  # refusal shows the error toast. Not async: pages are made synchronized
  # through the application env.
  use Brando.LiveCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Pages
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page
  alias Brando.Translations
  alias BrandoAdmin.LiveView.Listing.DeleteDescription

  setup %{current_user: user} do
    put_test_env(Page, translatable: [mode: :synchronized])
    put_test_env(Fragment, translatable: [mode: :synchronized])
    put_test_env(:tenancy_mode, :none)
    Brando.endpoint().subscribe("user:#{user.id}")

    source = Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, status: :published, creator: user)
    {:ok, english} = Translations.create_target(Page, source.id, :en, user)
    {:ok, english} = Pages.update_page(english.id, %{title: "About us", status: :published}, user)
    %{source: source, english: english}
  end

  defp open_listing(conn) do
    {:ok, view, _html} = live(conn, "/admin/pages")
    await_selector(view, ".list-row")
    view
  end

  defp dialog(view, entry) do
    render_hook(view, "describe_delete", %{"id" => to_string(entry.id)})
    assert_reply(view, reply)
    reply
  end

  defp delete(view, entry, choice, reply, extra \\ %{}) do
    params =
      Map.merge(
        %{
          "id" => to_string(entry.id),
          "translations" => choice,
          "translations_group" => reply.values.translations_group,
          "opener" => "action_default_delete_entry_#{entry.id}"
        },
        extra
      )

    render_click(view, "delete_entry", params)
  end

  defp toast do
    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: message} = payload}
    {message, payload[:level]}
  end

  defp option_values(%{choice: %{name: "translations", options: options}}), do: Enum.map(options, & &1.value)
  defp option_values(%{choice: choices}) when is_list(choices), do: option_values(%{choice: List.last(choices)})
  defp option_values(_reply), do: []

  defp trashed_at(entry), do: Repo.get!(Page, entry.id).deleted_at

  test "the dialog lists the published translation apart, and offers every choice", c do
    view = open_listing(c.conn)
    reply = dialog(view, c.source)

    assert option_values(reply) == ~w(delete transfer detach)
    assert %{translations_group: group} = reply.values
    assert group == Translations.source_group(Page, c.source.id).fingerprint

    # The published translation in a section of its own, with its language
    assert [section] =
             reply.html |> String.split(~s(<div class="admin-dialog-section">)) |> Enum.filter(&(&1 =~ "About us"))

    assert section =~ "[EN]"
    refute section =~ "Om oss"

    # Its select names it as the new source
    %{options: [_, %{select: select}, _]} = reply.choice
    assert [%{value: value, label: label}] = select.options
    assert value == to_string(c.english.id)
    assert label =~ "About us"
  end

  test "Delete with its translations trashes both, and restoring the source brings both back", c do
    view = open_listing(c.conn)
    delete(view, c.source, "delete", dialog(view, c.source))

    assert {_message, :success} = toast()
    assert trashed_at(c.source)
    assert trashed_at(c.english) == trashed_at(c.source)

    # The translation alone is refused while its source is in the trash
    trash = open_listing_trash(c.conn)
    render_click(trash, "undelete_entry", %{"id" => to_string(c.english.id)})
    assert {message, :error} = toast()
    assert message =~ "Om oss"
    assert trashed_at(c.english)

    render_click(trash, "undelete_entry", %{"id" => to_string(c.source.id)})
    assert {_message, :success} = toast()
    assert trashed_at(c.source) == nil
    assert trashed_at(c.english) == nil
  end

  test "Delete only this one, with the translations independent, keeps them", c do
    view = open_listing(c.conn)
    delete(view, c.source, "detach", dialog(view, c.source))

    assert {_message, :success} = toast()
    assert trashed_at(c.source)
    assert trashed_at(c.english) == nil
    assert %{synchronized: false} = Translations.get_member(Page, c.english.id)
  end

  test "Delete only this one, with a translation the source, moves the role to it", c do
    view = open_listing(c.conn)
    reply = dialog(view, c.source)
    delete(view, c.source, "transfer", reply, %{"translations_source" => to_string(c.english.id)})

    assert {_message, :success} = toast()
    assert trashed_at(c.source)
    assert %{role: :source} = Translations.get_member(Page, c.english.id)
  end

  test "a group changed since the dialog opened deletes nothing, and opens the dialog again", c do
    view = open_listing(c.conn)
    reply = dialog(view, c.source)
    # A draft published meanwhile
    {:ok, _} = Pages.update_page(c.english.id, %{status: :draft}, c.current_user)

    delete(view, c.source, "delete", reply)

    assert {_message, :error} = toast()
    assert_push_event(view, "b:confirm-click-again", %{id: opener})
    assert opener == "action_default_delete_entry_#{c.source.id}"
    assert trashed_at(c.source) == nil
    assert trashed_at(c.english) == nil
  end

  test "Delete selected still refuses a source, with the error toast", c do
    view = open_listing(c.conn)
    render_click(view, "delete_selected", %{"ids" => Jason.encode!([c.source.id])})

    assert {_message, :error} = toast()
    assert trashed_at(c.source) == nil
  end

  test "a page whose fragment is a source is refused, naming the fragment, in the error toast", c do
    page = Factory.insert(:page, title: "Kontakt", uri: "kontakt", language: :no, creator: c.current_user)

    fragment =
      Factory.insert(:fragment,
        page_id: page.id,
        key: "footer",
        title: "Bunntekst",
        language: :no,
        creator: c.current_user
      )

    {:ok, _} = Translations.create_target(Fragment, fragment.id, :en, c.current_user)

    view = open_listing(c.conn)
    render_click(view, "delete_entry", %{"id" => to_string(page.id), "fragments" => "delete"})

    assert {message, :error} = toast()
    assert message =~ "Bunntekst"
    assert trashed_at(page) == nil
  end

  defp open_listing_trash(conn) do
    {:ok, view, _html} = live(conn, "/admin/pages?status=deleted")
    view
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
          %{name: "Page editors"},
          ~w(brando.admin.access brando.pages.read brando.pages.update brando.pages.delete brando.pages.restore)
        )

      {:ok, readers} = Groups.create(scope, %{name: "Page readers"}, ~w(brando.admin.access brando.pages.read))
      {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)
      {:ok, :ok} = Groups.add_member(scope, readers.id, editor.id)
      Brando.endpoint().subscribe("user:#{editor.id}")
      editor_conn = Brando.Test.log_in_user(Brando.Test.Support.admin_conn(), editor)
      %{editor: editor, group: group, scope: scope, editor_conn: editor_conn}
    end

    test "someone who may not publish is not offered to delete the published translation, nor can force it", c do
      # The source a draft: deleting it takes no publish right
      {:ok, _} = Pages.update_page(c.source.id, %{status: :draft}, c.current_user)
      view = open_listing(c.editor_conn)
      reply = dialog(view, c.source)

      assert option_values(reply) == ~w(transfer detach)

      delete(view, c.source, "delete", reply)
      assert {_message, :error} = toast()
      assert trashed_at(c.source) == nil
      assert trashed_at(c.english) == nil
    end

    test "a permission revoked after the dialog opened changes nothing", c do
      {:ok, _} = Pages.update_page(c.source.id, %{status: :draft}, c.current_user)
      view = open_listing(c.editor_conn)
      reply = dialog(view, c.source)

      {:ok, :ok} = Groups.remove_member(c.scope, c.group.id, c.editor.id)
      delete(view, c.source, "detach", reply)

      assert trashed_at(c.source) == nil
      assert %{synchronized: true} = Translations.get_member(Page, c.english.id)
    end
  end

  describe "a translation the viewer may not read" do
    alias Brando.SyncPolicyTest.Article, as: PolicyArticle

    setup %{current_user: owner} do
      put_test_env(:authorization_mode, :groups)
      Boundary.put_scope(nil)
      on_exit(fn -> Boundary.put_scope(nil) end)
      {:ok, _} = Migration.run()
      scope = Scope.standalone(owner)
      reader = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})

      {:ok, group} =
        Groups.create(
          scope,
          %{name: "Article editors"},
          ~w(brando.admin.access authorization.policy_articles.read authorization.policy_articles.update brando.synctest_articles.delete)
        )

      {:ok, :ok} = Groups.add_member(scope, group.id, reader.id)

      {:ok, source} =
        Brando.SyncPolicyTest.create_article(%{title: "Egen", slug: "egen", language: "no", status: "draft"}, owner)

      {:ok, target} = Translations.create_target(PolicyArticle, source.id, :en, owner)
      {:ok, _} = Brando.SyncPolicyTest.update_article(target.id, %{title: "Hidden one"}, owner)

      # The reader made the source; the translation is someone else's
      Repo.update_all(from(a in PolicyArticle, where: a.id == ^source.id), set: [creator_id: reader.id])
      %{reader: reader, policy_source: Repo.get!(PolicyArticle, source.id), policy_target: target}
    end

    test "is not named, and no choice that would change it is offered", c do
      reply =
        Boundary.with_scope(Scope.standalone(c.reader), fn ->
          DeleteDescription.describe(PolicyArticle, c.policy_source)
        end)

      refute reply.html =~ "Hidden one"
      assert reply.html =~ "you may not see"
      assert reply.refused
    end

    test "a forged delete with it is refused on the server", c do
      fingerprint = Translations.source_group(PolicyArticle, c.policy_source.id).fingerprint

      assert {:error, _} =
               Translations.delete_keeping_translations(PolicyArticle, c.policy_source.id, nil, fingerprint, c.reader)

      assert %{synchronized: true} = Translations.get_member(PolicyArticle, c.policy_target.id)
      assert Repo.get(PolicyArticle, c.policy_source.id)
    end
  end
end

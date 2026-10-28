defmodule BrandoAdmin.FragmentWrapperAuthorityTest do
  # A fragment's `wrapper` is markup printed around it as it is, so only a
  # superuser sets it, as only a superuser writes module code. Editors keep
  # editing the rest of the fragment and may copy one that has a wrapper.
  use Brando.LiveCase

  alias Brando.Authorization.{Groups, Migration, Scope}
  alias Brando.Pages
  alias Brando.Pages.Fragment
  alias Brando.Test.Users, as: TestUsers

  @wrapper ~s(<div data-wrapper="set">{{ content }}</div>)

  defp fragment!, do: Factory.insert(:fragment, title: "Footer", wrapper: nil)

  # Submits the form with `params` added, as a browser that sends a field
  # the form does not show would. Returns the form as it rendered.
  defp save_from_form(conn, fragment, params) do
    {:ok, view, _} = live(conn, "/admin/pages/fragments/update/#{fragment.id}")
    html = render_async(view, 5_000)
    # The first submit has the browser collect the form; the second saves
    view |> element("#fragment_form_form") |> render_submit(%{"fragment" => params})
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> element("#fragment_form_form") |> render_submit(%{"fragment" => params})
    assert_redirect(view, 3_000)
    html
  end

  describe "legacy mode" do
    test "an editor's save of the form leaves the wrapper and keeps the rest" do
      editor = TestUsers.insert_user(role: :editor)
      fragment = fragment!()
      conn = log_in_user(build_conn(), editor)

      html = save_from_form(conn, fragment, %{"wrapper" => @wrapper, "title" => "Edited footer"})
      refute html =~ "fragment[wrapper]"

      saved = Repo.get!(Fragment, fragment.id)
      assert saved.wrapper == nil
      assert saved.title == "Edited footer"
    end

    test "an editor cannot set a wrapper through the context, and may copy a fragment that has one" do
      editor = TestUsers.insert_user(role: :editor)
      fragment = fragment!()

      assert {:error, :forbidden} = Pages.update_fragment(fragment.id, %{wrapper: @wrapper}, editor)

      assert {:error, :forbidden} =
               Pages.create_fragment(%{parent_key: "p", key: "k", language: "en", wrapper: @wrapper}, editor)

      assert Repo.get!(Fragment, fragment.id).wrapper == nil

      assert {:ok, %{title: "Renamed"}} = Pages.update_fragment(fragment.id, %{title: "Renamed"}, editor)

      Repo.update!(Ecto.Changeset.change(fragment, wrapper: @wrapper))
      assert {:ok, copy} = Pages.duplicate_fragment(fragment.id, editor)
      assert copy.wrapper == @wrapper
    end

    test "a superuser sets the wrapper from the form", %{conn: conn} do
      fragment = fragment!()
      assert save_from_form(conn, fragment, %{"wrapper" => @wrapper}) =~ "fragment[wrapper]"
      assert Repo.get!(Fragment, fragment.id).wrapper == @wrapper
    end
  end

  describe "groups mode" do
    setup %{current_user: owner} do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      editor = TestUsers.insert_user(role: :editor)
      {:ok, _} = Migration.run()

      scope = Scope.standalone(owner)
      keys = ["brando.admin.access", "brando.pages_fragments.read", "brando.pages_fragments.update"]
      {:ok, group} = Groups.create(scope, %{name: "Fragment editors"}, keys)
      {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)

      %{owner: owner, editor: editor}
    end

    test "only a superuser sets the wrapper", %{owner: owner, editor: editor} do
      fragment = fragment!()

      assert {:error, :forbidden} = Pages.update_fragment(fragment.id, %{wrapper: @wrapper}, editor)
      assert {:ok, %{title: "Renamed"}} = Pages.update_fragment(fragment.id, %{title: "Renamed"}, editor)
      assert {:ok, %{wrapper: @wrapper}} = Pages.update_fragment(fragment.id, %{wrapper: @wrapper}, owner)
    end
  end
end

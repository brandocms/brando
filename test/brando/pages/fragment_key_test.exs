defmodule Brando.Pages.FragmentKeyTest do
  # A fragment's parent key and key are identifiers an editor sets: the
  # changeset holds them to that, and what is stored already prints escaped.
  # Not async: the missing-fragment box depends on `Brando.env/0`.
  use Brando.LiveCase

  import ExUnit.CaptureLog
  import Phoenix.Component, only: [sigil_H: 2]

  alias Brando.Authorization.{Groups, Migration, Scope}
  alias Brando.Pages
  alias Brando.Pages.Fragment
  alias Brando.Test.Users, as: TestUsers

  @marker ~s(<i data-marker="key"></i>)
  @closing ~s("><i data-marker="key"></i>)
  @crafted [@marker, @closing, "a\n", "a\tb", "a&b", "a=b", "a'b", ~s(a"b), "{{ a }}", "{% a %}", " a", "a ", "", " "]

  defp fragment!(attrs \\ []), do: Factory.insert(:fragment, Keyword.merge([title: "Footer", wrapper: nil], attrs))

  defp errors(params) do
    %Fragment{}
    |> Fragment.changeset(Map.merge(%{parent_key: "partials", key: "footer", language: "en"}, params), %{id: 1})
    |> Map.fetch!(:errors)
    |> Keyword.keys()
    |> Enum.filter(&(&1 in [:parent_key, :key]))
  end

  defp to_html(safe), do: Phoenix.HTML.safe_to_string(safe)

  defp markers(html), do: html |> Floki.parse_fragment!() |> Floki.find("[data-marker]")

  # Submits the form, as `BrandoAdmin.FragmentWrapperAuthorityTest` does, and
  # returns the view, which redirects when the save goes through.
  defp submit_form(conn, fragment, params) do
    {:ok, view, _} = live(conn, "/admin/pages/fragments/update/#{fragment.id}")
    render_async(view, 5_000)
    view |> element("#fragment_form_form") |> render_submit(%{"fragment" => params})
    assert_push_event(view, "b:submit", %{}, 2_000)
    html = view |> element("#fragment_form_form") |> render_submit(%{"fragment" => params})
    {view, html}
  end

  describe "the key format" do
    test "keeps the keys projects use" do
      for key <- [
            "partials",
            "footer",
            "contact_card",
            "site-footer",
            "my/fragment",
            "about/team",
            "/about",
            "-footer",
            "2024/report",
            "footer.en",
            "om-oss/kontakt",
            "smørbrød",
            "_private",
            "footer (copy)",
            "footer (kopi) (kopi)"
          ] do
        assert errors(%{key: key}) == [], "key #{inspect(key)} was refused"
        assert errors(%{parent_key: key}) == [], "parent key #{inspect(key)} was refused"
      end
    end

    test "refuses anything else, in both fields" do
      for key <- @crafted do
        assert :key in errors(%{key: key}), "key #{inspect(key)} was accepted"
        assert :parent_key in errors(%{parent_key: key}), "parent key #{inspect(key)} was accepted"
      end
    end

    test "leaves a stored key alone until it changes" do
      fragment = fragment!(key: "Stored&key", parent_key: "Stored&parent")

      changeset = Fragment.changeset(fragment, %{title: "Renamed"}, %{id: 1})
      assert changeset.valid?
      assert Repo.get!(Fragment, fragment.id).key == "Stored&key"
    end
  end

  describe "legacy mode" do
    setup do
      editor = TestUsers.insert_user(role: :editor)
      %{editor: editor}
    end

    test "the context refuses an editor's crafted key and keeps the rest of their edits working", %{editor: editor} do
      fragment = fragment!()

      assert {:error, %Ecto.Changeset{} = changeset} = Pages.update_fragment(fragment.id, %{key: @marker}, editor)
      assert Keyword.has_key?(changeset.errors, :key)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Pages.update_fragment(fragment.id, %{parent_key: @marker}, editor)

      assert Keyword.has_key?(changeset.errors, :parent_key)

      assert {:error, %Ecto.Changeset{}} =
               Pages.create_fragment(%{parent_key: "partials", key: @marker, language: "en"}, editor)

      assert {:ok, %{key: "my/fragment"}} = Pages.update_fragment(fragment.id, %{key: "my/fragment"}, editor)
    end

    test "the form refuses an editor's crafted key", %{editor: editor} do
      fragment = fragment!()
      conn = log_in_user(build_conn(), editor)

      {view, _html} = submit_form(conn, fragment, %{"key" => @marker})

      assert Process.alive?(view.pid)
      assert Repo.get!(Fragment, fragment.id).key == fragment.key
    end

    test "a copy's key fits, and saves when edited further", %{editor: editor} do
      fragment = fragment!(key: "footer")

      assert {:ok, %{key: "footer" <> _ = key} = copy} = Pages.duplicate_fragment(fragment.id, editor)
      assert key != "footer"
      assert errors(%{key: key}) == []
      assert {:ok, %{key: "footer (copy) 2"}} = Pages.update_fragment(copy.id, %{key: "footer (copy) 2"}, editor)
    end

    test "a copy of a stored key that doesn't fit still goes through", %{editor: editor} do
      fragment = fragment!(key: "Stored&key")

      assert {:ok, %{key: "Stored&key" <> _}} = Pages.duplicate_fragment(fragment.id, editor)
    end

    test "an editor still saves a stored key that doesn't fit, unchanged", %{editor: editor} do
      fragment = fragment!(key: "Stored&key")

      assert {:ok, %{title: "Renamed", key: "Stored&key"}} =
               Pages.update_fragment(fragment.id, %{title: "Renamed"}, editor)
    end
  end

  describe "restoring a revision" do
    # A revision taken while the key was `key`, and a later rename to `renamed`
    defp old_revision!(key, renamed, user) do
      fragment = fragment!(key: key)
      {:ok, _} = Brando.Revisions.create_revision(fragment, user)
      [%{revision: old}] = Repo.all(Brando.Revisions.Revision)

      {:ok, changed} = Pages.update_fragment(fragment.id, %{key: renamed}, user)
      {:ok, _} = Brando.Revisions.create_revision(changed, user)

      {fragment, old}
    end

    test "is refused when it would bring back a key that doesn't fit", %{current_user: user} do
      {fragment, old} = old_revision!("Stored&key", "footer", user)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Brando.Revisions.set_entry_to_revision(Fragment, fragment.id, old, user)

      assert Keyword.has_key?(changeset.errors, :key)
      assert Repo.get!(Fragment, fragment.id).key == "footer"
    end

    test "goes through when the fragment still has that key", %{current_user: user} do
      fragment = fragment!(key: "Stored&key")
      {:ok, _} = Brando.Revisions.create_revision(fragment, user)
      [%{revision: old}] = Repo.all(Brando.Revisions.Revision)

      {:ok, changed} = Pages.update_fragment(fragment.id, %{title: "Changed"}, user)
      {:ok, _} = Brando.Revisions.create_revision(changed, user)

      assert {:ok, %{title: "Footer", key: "Stored&key"}} =
               Brando.Revisions.set_entry_to_revision(Fragment, fragment.id, old, user)
    end

    # Renaming the fragment is what the revision conflicts with, so a further
    # rename doesn't free it
    test "stays refused after the fragment is renamed again", %{current_user: user} do
      {fragment, old} = old_revision!("Stored&key", "footer", user)

      {:ok, _} = Pages.update_fragment(fragment.id, %{key: "site-footer"}, user)

      assert {:error, %Ecto.Changeset{}} = Brando.Revisions.set_entry_to_revision(Fragment, fragment.id, old, user)
      assert Repo.get!(Fragment, fragment.id).key == "site-footer"
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

    test "a holder of the update grant cannot store a crafted key, nor can the owner", %{owner: owner, editor: editor} do
      fragment = fragment!()

      assert {:error, %Ecto.Changeset{}} = Pages.update_fragment(fragment.id, %{key: @marker}, editor)
      assert {:error, %Ecto.Changeset{}} = Pages.update_fragment(fragment.id, %{parent_key: @marker}, editor)
      assert {:error, %Ecto.Changeset{}} = Pages.update_fragment(fragment.id, %{key: @marker}, owner)

      assert {:ok, %{key: "my/fragment"}} = Pages.update_fragment(fragment.id, %{key: "my/fragment"}, editor)
      assert Repo.get!(Fragment, fragment.id).key == "my/fragment"
    end
  end

  describe "a stored crafted key, in the wrapper" do
    test "prints escaped in {{ key }} and {{ parent_key }}" do
      fragment = %Fragment{
        status: :published,
        parent_key: @marker,
        key: @closing,
        language: :en,
        rendered_blocks: "content",
        wrapper: ~s(<section data-parent="{{ parent_key }}" data-key="{{ key }}">{{ parent_key }}{{ content }}</section>)
      }

      html = fragment |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      assert markers(html) == []
      assert [{"section", attrs, [text]}] = Floki.parse_fragment!(html)
      assert text == @marker <> "content"
      assert {"data-parent", @marker} in attrs
      assert {"data-key", @closing} in attrs
    end

    test "cannot bring a placeholder of its own" do
      fragment = %Fragment{
        status: :published,
        parent_key: "{{ key }}",
        key: @marker,
        language: :en,
        rendered_blocks: "",
        wrapper: "{{ parent_key }}"
      }

      html = fragment |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      assert html == "&#123;&#123; key &#125;&#125;"
      refute html =~ "data-marker"
    end
  end

  describe "the missing-fragment box in development" do
    setup do
      put_test_env(:env, :dev)
    end

    test "render_fragment/2 prints the map's keys and the asked-for key escaped" do
      html = %{@marker => %Fragment{}} |> Pages.render_fragment(@closing) |> to_html()

      assert html =~ "Missing page fragment"
      assert markers(html) == []
      assert html =~ "&lt;i"
    end

    test "render_fragment/3 prints the keys escaped" do
      html = "partials" |> Pages.render_fragment(@marker, "en") |> to_html()
      assert html =~ "Missing page fragment"
      assert markers(html) == []

      assert @marker |> Pages.render_fragment("footer", "en") |> to_html() |> markers() == []
    end

    test "fetch_fragment/2 prints the key escaped" do
      html = @marker |> Pages.fetch_fragment() |> to_html()
      assert html =~ "Missing page fragment"
      assert markers(html) == []
    end

    test "render_embedded_fragment/3 prints the keys escaped" do
      html = "partials" |> Pages.render_embedded_fragment(@marker, "en") |> to_html()
      assert html =~ "Missing page fragment"
      assert markers(html) == []
    end

    test "the component shows the box too" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Brando.HTML.fragment parent_key="partials" key="missing" language="en" />
        """)

      assert html =~ "Missing page fragment"
    end
  end

  describe "the missing-fragment box anywhere else" do
    setup do
      previous = Logger.level()
      Logger.configure(level: :warning)
      on_exit(fn -> Logger.configure(level: previous) end)
    end

    test "render_fragment/2 prints nothing and logs" do
      fragments = %{@marker => %Fragment{}}

      log =
        capture_log(fn ->
          assert fragments |> Pages.render_fragment("footer") |> to_html() == ""
        end)

      assert log =~ "Missing page fragment"
      assert log =~ "footer"
    end

    test "render_fragment/3, fetch_fragment/2 and render_embedded_fragment/3 print nothing" do
      capture_log(fn ->
        assert "partials" |> Pages.render_fragment("nope", "en") |> to_html() == ""
        assert "nope" |> Pages.fetch_fragment("en") |> to_html() == ""
        assert "partials" |> Pages.render_embedded_fragment("nope", "en") |> to_html() == ""
      end)
    end

    test "a crafted key can't break the log line" do
      log = capture_log(fn -> Pages.render_fragment(%{"a\nb" => %Fragment{}}, "c\nd") end)
      assert log =~ "Missing page fragment"
      refute log =~ "c\nd"
    end
  end
end

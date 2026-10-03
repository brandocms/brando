defmodule Brando.FrontendEditTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Brando.FrontendEditFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Factory
  alias Brando.FrontendEdit
  alias Brando.FrontendEdit.Manifest
  alias Brando.FrontendEdit.Targets
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page

  setup do
    user = Factory.insert(:random_user, role: :superuser)
    on_exit(fn -> FrontendEdit.deactivate() end)
    Map.put(page_with_blocks(user), :user, user)
  end

  describe "enabled?/0" do
    test "is off unless switched on in config" do
      previous = Application.get_env(:brando, FrontendEdit)
      on_exit(fn -> restore_env(previous) end)

      Application.delete_env(:brando, FrontendEdit)
      refute FrontendEdit.enabled?()

      Application.put_env(:brando, FrontendEdit, enabled: false)
      refute FrontendEdit.enabled?()

      Application.put_env(:brando, FrontendEdit, enabled: true)
      assert FrontendEdit.enabled?()
    end
  end

  describe "rendered_html/2" do
    test "is the stored HTML outside edit mode", %{page: page} do
      assert FrontendEdit.rendered_html(page, :blocks) == page.rendered_blocks
      refute page.rendered_blocks =~ "[+:B<"
      assert Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(page)) =~ "Hello from the intro"
    end

    test "marks the field and its blocks in edit mode, otherwise matching the stored HTML",
         %{page: page, intro: intro, container: container, child: child} do
      html = FrontendEdit.with_active(fn -> FrontendEdit.rendered_html(page, :blocks) end)
      key = FrontendEdit.field_key(Page, page.id, :blocks)

      assert String.starts_with?(html, "<!-- [+:F<#{key}>] -->")
      assert String.ends_with?(html, "<!-- [-:F<#{key}>] -->")

      for block <- [intro, container, child] do
        assert html =~ "<!-- [+:B<#{block.uid}>] -->"
        assert html =~ "<!-- [-:B<#{block.uid}>] -->"
      end

      assert strip_markers(html) == strip_markers(page.rendered_blocks)
    end

    test "every print path hands out the annotated HTML in edit mode", %{page: page} do
      FrontendEdit.with_active(fn ->
        assert Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(page)) =~ "[+:F<"

        rendered = render_component(&Brando.HTML.render_blocks/1, entry: page)

        assert rendered =~ "[+:F<"
      end)
    end

    test "a fragment embedded in a block carries its own field and blocks", %{user: user, module: module} do
      %{fragment: fragment, block: fragment_text} = fragment_with_block(user, module)
      embed = fragment_block(fragment, user, Page.Blocks)
      page = Factory.insert(:page, creator: user, uri: "with-fragment")
      attach(Page.Blocks, page, [embed])
      {:ok, page} = Brando.Content.Blocks.render_entry(Page, page.id)

      html = FrontendEdit.with_active(fn -> FrontendEdit.rendered_html(page, :blocks) end)

      assert html =~ "<!-- [+:B<#{embed.uid}>] -->"
      assert html =~ "<!-- [+:F<#{FrontendEdit.field_key(Fragment, fragment.id, :blocks)}>] -->"
      assert html =~ "<!-- [+:B<#{fragment_text.uid}>] -->"
      assert strip_markers(html) == strip_markers(page.rendered_blocks)
    end

    test "falls back to the stored HTML for entries that are not blocks" do
      FrontendEdit.with_active(fn ->
        assert FrontendEdit.rendered_html(%{rendered_blocks: "<p>Stored</p>"}, :blocks) == "<p>Stored</p>"
        assert FrontendEdit.rendered_html(nil, :blocks) == nil
      end)
    end
  end

  describe "single-entry queries" do
    test "return annotated entries in edit mode, and the cache keeps the stored HTML", %{page: page} do
      opts = %{matches: %{id: page.id}, cache: {:ttl, :infinite}}

      {:ok, annotated} = FrontendEdit.with_active(fn -> Brando.Pages.get_page(opts) end)
      assert annotated.rendered_blocks =~ "[+:F<"

      {:ok, cached} = Brando.Pages.get_page(opts)
      assert cached.rendered_blocks == page.rendered_blocks
    end

    test "leave revisions alone", %{page: page} do
      assert FrontendEdit.annotate_query_result({:ok, page}, %{revision: 1}) == {:ok, page}
    end

    test "are untouched outside edit mode", %{page: page} do
      {:ok, entry} = Brando.Pages.get_page(%{matches: %{id: page.id}})
      assert entry.rendered_blocks == page.rendered_blocks
    end
  end

  describe "field keys" do
    test "round-trip for block fields, and refuse anything else", %{page: page} do
      key = FrontendEdit.field_key(Page, page.id, :blocks)
      assert FrontendEdit.parse_field_key(key) == {:ok, {Page, page.id, :blocks}}

      assert FrontendEdit.parse_field_key("Brando.Pages.Page:#{page.id}:title") == :error
      assert FrontendEdit.parse_field_key("Brando.Users.User:1:blocks") == :error
      assert FrontendEdit.parse_field_key("Not.A.Module.At.All:1:blocks") == :error
      assert FrontendEdit.parse_field_key("Brando.Pages.Page:abc:blocks") == :error
      assert FrontendEdit.parse_field_key(nil) == :error
    end
  end

  describe "targets" do
    test "a click inside a module opens the module", %{intro: intro, page: page} do
      assert {:ok, resolved} = Targets.resolve(intro.uid)
      assert resolved.target.uid == intro.uid
      assert resolved.root.uid == intro.uid
      assert resolved.path == []
      assert resolved.owner == {Page, page.id, :blocks}
    end

    test "a module in a container opens the module, with the container on the way", %{container: container, child: child} do
      assert {:ok, resolved} = Targets.resolve(child.uid)
      assert resolved.target.uid == child.uid
      assert resolved.root.uid == container.uid
      assert resolved.path == [container.uid]
    end

    test "the container itself opens the container", %{container: container} do
      assert {:ok, %{target: %{uid: uid}, path: []}} = Targets.resolve(container.uid)
      assert uid == container.uid
    end

    test "an unknown uid resolves to nothing" do
      assert Targets.resolve("nope") == {:error, :not_found}
      assert Targets.resolve(nil) == {:error, :not_found}
    end

    test "collections and multi entries open the module that owns them" do
      owner = %{id: 1, uid: "owner", type: :module}
      slot = %{id: 2, uid: "slot", type: :slot}
      in_slot = %{id: 3, uid: "in-slot", type: :module}
      container = %{id: 4, uid: "container", type: :container}
      entry = %{id: 5, uid: "entry", type: :module_entry}

      assert Targets.target([in_slot, slot, owner, container]).uid == "owner"
      assert Targets.target([entry, owner]).uid == "owner"
      assert Targets.target([container]).uid == "container"
      assert Targets.ancestors([in_slot, slot, owner, container], owner) == ["container"]
    end
  end

  describe "manifest" do
    test "maps every marked block to what a click opens, and names it",
         %{page: page, user: user, intro: intro, container: container, child: child} do
      html = FrontendEdit.with_active(fn -> FrontendEdit.rendered_html(page, :blocks) end)
      manifest = Manifest.build(html, user)
      key = FrontendEdit.field_key(Page, page.id, :blocks)

      assert %{kind: _, label: "About us", editable: true, shared: false} = manifest.owners[key]
      assert manifest.blocks[intro.uid] == %{target: intro.uid, owner: key, label: "Text"}
      assert manifest.blocks[child.uid].target == child.uid
      assert manifest.blocks[container.uid].target == container.uid
    end

    test "marks fragments as shared, with their usage", %{user: user, module: module} do
      %{fragment: fragment, block: text} = fragment_with_block(user, module)
      page = Factory.insert(:page, creator: user, uri: "embeds")
      attach(Page.Blocks, page, [fragment_block(fragment, user, Page.Blocks)])

      html = FrontendEdit.with_active(fn -> FrontendEdit.rendered_html(fragment, :blocks) end)
      manifest = Manifest.build(html, user)
      key = FrontendEdit.field_key(Fragment, fragment.id, :blocks)

      assert %{shared: true, usage: 1} = manifest.owners[key]
      assert manifest.blocks[text.uid].owner == key
    end

    test "follows group permissions to update the entry", %{page: page, user: user} do
      Brando.Test.Support.put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      alias Brando.Authorization.{Catalog, Groups, Scope}

      reader = Factory.insert(:random_user, role: :user)
      scope = Scope.standalone(user)

      {:ok, readers} =
        Groups.create(scope, %{name: "Readers"}, [Catalog.get(:access, :backend).key, Catalog.get(:read, Page).key])

      {:ok, :ok} = Groups.add_member(scope, readers.id, reader.id)

      html = FrontendEdit.with_active(fn -> FrontendEdit.rendered_html(page, :blocks) end)
      key = FrontendEdit.field_key(Page, page.id, :blocks)

      assert %{editable: false} = Manifest.build(html, reader).owners[key]
      refute Manifest.editable?({Page, page.id, :blocks}, reader)

      {:ok, editors} = Groups.create(scope, %{name: "Page editors"}, [Catalog.get(:update, Page).key])
      {:ok, :ok} = Groups.add_member(scope, editors.id, reader.id)

      assert %{editable: true} = Manifest.build(html, reader).owners[key]
    end

    test "only offers block fields the entry's admin form shows", %{page: page, user: user} do
      assert Manifest.editable?({Page, page.id, :blocks}, user)
      refute Manifest.editable?({Page, page.id, :not_a_field}, user)
    end

    test "ignores markers it cannot resolve", %{user: user} do
      html = "<!-- [+:F<Brando.Users.User:1:blocks>] --><!-- [+:B<missing>] --><!-- [-:B<missing>] -->"
      assert Manifest.build(html, user) == %{owners: %{}, blocks: %{}}
    end
  end

  test "scheduled_revision?/2 is false without a scheduled revision", %{page: page} do
    refute FrontendEdit.scheduled_revision?(Page, page.id)
  end

  defp restore_env(nil), do: Application.delete_env(:brando, FrontendEdit)
  defp restore_env(value), do: Application.put_env(:brando, FrontendEdit, value)
end

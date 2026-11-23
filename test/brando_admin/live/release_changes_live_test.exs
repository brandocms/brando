defmodule BrandoAdmin.ReleaseChangesLiveTest do
  # Block modules → Release changes (brandocms/brando#3612, round 2)
  use Brando.LiveCase, async: false

  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{DefinitionApply, Definitions, Module}
  alias Brando.Content.Definitions.Release
  alias Brando.Content.Definitions.Release.{Batches, Verify}
  alias Brando.{Factory, Repo}
  alias Ecto.Changeset

  @path "/admin/config/content/modules/release"

  setup %{current_user: user} do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
    c = Brando.ProposalFixtures.context()
    case_c = %{c | user: user}
    path = Path.join(System.tmp_dir!(), "brando-review-live-#{System.unique_integer([:positive])}")
    {:ok, _} = Definitions.export(path, user, uids: [c.text_module.uid, c.case_module.uid])
    File.rm!(Path.join(path, "modules.lock.json"))
    put_test_env(Definitions, release_path: path)
    {:ok, %{adopted: 2}} = Release.plan(user: user.id, version: "1.0.0")
    Verify.clear()
    on_exit(fn -> File.rm_rf!(path) end)
    Map.put(case_c, :path, path)
  end

  defp release_template!(c, name, code), do: File.write!(Path.join(c.path, "content/#{name}.liquid"), code)

  defp text(c), do: Repo.get!(Module, c.text_module.id)
  defp case_module(c), do: Repo.get!(Module, c.case_module.id)

  defp manual(fun), do: Oban.Testing.with_testing_mode(:manual, fun)

  defp eventually(view, fun, tries \\ 100) do
    html = render(view)

    cond do
      fun.(html) -> html
      tries == 0 -> flunk("never rendered as expected:\n" <> html)
      true -> Process.sleep(20) && eventually(view, fun, tries - 1)
    end
  end

  test "lists the release's changes with a summary, and the template diff", %{conn: conn} = c do
    release_template!(c, "text", "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")

    {:ok, view, html} = live(conn, @path)
    assert html =~ "Release changes"
    assert has_element?(view, "[data-testid=release-row][data-uid=#{c.text_module.uid}]")
    assert has_element?(view, "[data-testid=release-total] strong", "2")
    assert has_element?(view, "[data-testid=release-apply]", "Apply 1 change…")
    # The template diff, highlighted
    assert html =~ ~s(class="tok-str")
    assert html =~ "v2"

    view |> element("[data-testid=release-tab-refs]") |> render_click()
    assert has_element?(view, "[data-testid=release-structure]")
  end

  test "Verify renders the entries with the release's definitions, and the per-block diff", %{conn: conn} = c do
    release_template!(c, "text", "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")
    before = Repo.all(from(p in Brando.Pages.Page, order_by: p.id, select: {p.id, p.rendered_blocks}))

    {:ok, view, _html} = live(conn, @path)
    view |> element("[data-testid=release-verify-row]") |> render_click()
    html = eventually(view, &(&1 =~ "2 of 2 entries verified"))
    assert html =~ "3 blocks differ"
    assert Repo.all(from(p in Brando.Pages.Page, order_by: p.id, select: {p.id, p.rendered_blocks})) == before

    view
    |> element("[data-testid=release-open-diff][phx-value-key='Brando.Pages.Page:#{c.identity.id}']")
    |> render_click()

    assert has_element?(view, "#release-block-diff")
    assert render(view) =~ "class=&quot;v2&quot;" or render(view) =~ ~s(<span class="tok-str">&quot;v2&quot;</span>)
  end

  test "applies the selected definitions only, then Keep confirms the apply", %{conn: conn} = c do
    release_template!(c, "text", "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")
    release_template!(c, "case", "<div class=\"case v2\">{{ heading }}</div>")

    manual(fn ->
      {:ok, view, _html} = live(conn, @path)

      # The Case module is left out
      view
      |> element("[data-testid=release-row][data-uid=#{c.case_module.uid}] [data-testid=release-row-check]")
      |> render_click()

      view |> element("[data-testid=release-apply]") |> render_click()
      assert has_element?(view, "#release-confirm[data-open=true]")
      assert render(view) =~ "Not included:"
      view |> element("[data-testid=release-confirm-apply]") |> render_click()

      assert text(c).code =~ "v2"
      refute case_module(c).code =~ "v2"
      assert has_element?(view, "[data-testid=release-banner]")
      assert batch = Batches.pending()
      assert [%{"uid" => uid}] = batch.definitions["items"]
      assert uid == c.text_module.uid

      view |> element("[data-testid=release-keep]") |> render_click()
      refute has_element?(view, "[data-testid=release-banner]")
      assert %{confirmed_how: :kept} = Batches.get(batch.batch_id)
    end)
  end

  test "a container and the palette it names are one row, with the template diff and entries, applied together",
       %{conn: conn} = c do
    {:ok, palette} =
      Brando.Content.create_palette(
        %{
          "name" => "Paper",
          "namespace" => "site",
          "key" => "paper",
          "status" => "published",
          "colors" => [%{"name" => "Background", "key" => "background", "hex_value" => "#ffffff"}]
        },
        c.user
      )

    {:ok, container} =
      Brando.Content.create_container(
        %{
          "name" => "Tinted",
          "namespace" => "Sections",
          "code" => "<section>{{ content }}</section>",
          "type" => "liquid",
          "palette_id" => palette.id
        },
        c.user
      )

    # The release ships both, as this database has them; then changes them
    styles = c.path <> "-styles"
    {:ok, _} = Definitions.export(styles, c.user, uids: [container.uid])
    on_exit(fn -> File.rm_rf!(styles) end)
    for dir <- ~w(palettes containers), do: File.cp_r!(Path.join(styles, dir), Path.join(c.path, dir))
    {:ok, %{adopted: 2}} = Release.plan(user: c.user.id, version: "1.0.0")
    File.write!(Path.join(c.path, "containers/tinted.liquid"), "<aside class=\"from-release\">{{ content }}</aside>")
    palette_file = Path.join(c.path, "palettes/paper.exs")
    File.write!(palette_file, String.replace(File.read!(palette_file), "#ffffff", "#fafafa"))

    manual(fn ->
      {:ok, view, _html} = live(conn, @path)
      row = "[data-testid=release-row][data-uid='#{container.uid}']"
      assert has_element?(view, row)
      refute has_element?(view, "[data-testid=release-row][data-uid='#{palette.uid}']")

      view |> element(row) |> render_click()
      assert render(view) =~ "from-release"
      assert has_element?(view, "[data-testid=release-tab-entries]")
      refute has_element?(view, "[data-testid=release-tab-preview]")

      view |> element("[data-testid=release-apply]") |> render_click()
      view |> element("[data-testid=release-confirm-apply]") |> render_click()

      assert Repo.get!(Brando.Content.Container, container.id).code =~ "from-release"
      assert [%{hex_value: "#fafafa"}] = Repo.get!(Brando.Content.Palette, palette.id).colors
      assert Batches.pending().definitions["items"] |> Enum.map(& &1["kind"]) |> Enum.sort() == ["container", "palette"]
    end)
  end

  test "Keep and Revert wait until every render is done", %{conn: conn} = c do
    release_template!(c, "text", "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")

    manual(fn ->
      {:ok, _} = Release.apply([c.text_module.uid], user: c.user.id, wait: false)
      {:ok, view, html} = live(conn, @path)
      assert html =~ "re-rendering entries"
      assert has_element?(view, "[data-testid=release-keep][disabled]")
      assert has_element?(view, "[data-testid=release-revert][disabled]")

      Oban.drain_queue(queue: :default)
      send(view.pid, :tick)
      eventually(view, &(not (&1 =~ "re-rendering entries")))
      refute has_element?(view, "[data-testid=release-keep][disabled]")
    end)
  end

  test "Revert restores the definitions the apply replaced", %{conn: conn} = c do
    original = text(c).code
    release_template!(c, "text", "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")
    {:ok, _} = Release.apply([c.text_module.uid], user: c.user.id, wait: false)

    {:ok, view, _html} = live(conn, @path)
    assert has_element?(view, "[data-testid=release-banner]")
    view |> element("[data-testid=release-revert]") |> render_click()

    assert text(c).code == original
    refute has_element?(view, "[data-testid=release-banner]")
    assert has_element?(view, "[data-testid=release-row][data-uid=#{c.text_module.uid}]")
  end

  test "an edit here after the apply makes its revert a conflict, named in the banner", %{conn: conn} = c do
    release_template!(c, "text", "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")
    {:ok, _} = Release.apply([c.text_module.uid], user: c.user.id, wait: false)
    editor = Factory.insert(:random_user, name: "Kari Nordmann")
    edited = text(c) |> Changeset.change(code: "<p class=\"edited\">{{ heading }}</p>") |> Repo.update!()
    Brando.Activity.record(:updated, edited, editor, fields: ["code"])

    {:ok, view, html} = live(conn, @path)
    assert html =~ "changed here after the apply"
    assert html =~ "Kari Nordmann"

    view |> element("[data-testid=release-revert]") |> render_click()
    assert text(c).code =~ "edited"
  end

  test "the applied row on screen goes with the banner when the apply is kept", %{conn: conn} = c do
    release_template!(c, "text", "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")
    {:ok, _} = Release.apply([c.text_module.uid], user: c.user.id, wait: false)

    {:ok, view, _html} = live(conn, @path)
    view |> element("[data-testid=release-applied-row]") |> render_click()
    view |> element("[data-testid=release-keep]") |> render_click()
    refute has_element?(view, "[data-testid=release-banner]")
    assert render(view) =~ "Release changes"
  end

  test "a removed var is ready to apply, and the applied module links to Resolve blocks", %{conn: conn} = c do
    block =
      Repo.insert!(%Brando.Content.Block{
        uid: Brando.Utils.generate_uid(),
        type: :module,
        module_id: c.case_module.id,
        creator_id: c.user.id
      })

    Repo.insert!(%Brando.Content.Var{block_id: block.id, key: "wide", type: :boolean, label: %{"en" => "Wide"}})
    exs = Path.join(c.path, "content/case.exs")
    source = File.read!(exs)
    without = Regex.replace(~r/\n    var "wide", "boolean" do\n.*?\n    end\n/s, source, "\n")
    assert without != source
    File.write!(exs, without)

    manual(fn ->
      {:ok, view, _html} = live(conn, @path)
      view |> element("[data-testid=release-row][data-uid=#{c.case_module.uid}]") |> render_click()
      assert has_element?(view, "[data-testid=release-removals] li[data-uid=#{c.case_module.uid}]")
      refute has_element?(view, "[data-testid=release-resolve-blocks]")

      view |> element("[data-testid=release-apply]") |> render_click()
      view |> element("[data-testid=release-confirm-apply]") |> render_click()
      assert Repo.get_by(Brando.Content.Var, block_id: block.id, key: "wide")

      view |> element("[data-testid=release-applied-row][data-uid=#{c.case_module.uid}]") |> render_click()

      assert has_element?(
               view,
               ~s([data-testid=release-resolve-blocks][href="/admin/config/content/modules/update/#{c.case_module.id}/stale-blocks"])
             )
    end)
  end

  describe "a conflict" do
    setup c do
      release_template!(c, "text", "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")
      {:ok, _} = Release.apply([c.text_module.uid], user: c.user.id, wait: false)
      {:ok, _} = Batches.keep(Batches.pending(), c.user)
      text(c) |> Changeset.change(code: "<p class=\"here\">{{ heading }}</p>{% ref refs.body %}") |> Repo.update!()
      release_template!(c, "text", "<p class=\"v3\">{{ heading }}</p>{% ref refs.body %}")
      :ok
    end

    test "shows three versions and isn't applied until a choice", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, @path)
      view |> element("[data-testid=release-row][data-uid=#{c.text_module.uid}]") |> render_click()
      assert has_element?(view, "[data-testid=release-threeway]")
      assert has_element?(view, "[data-testid=release-row][data-uid=#{c.text_module.uid}] input[disabled]")
    end

    test "using the release's version replaces the edit", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, @path)
      view |> element("[data-testid=release-row][data-uid=#{c.text_module.uid}]") |> render_click()
      view |> element("[data-testid=release-choice-release]") |> render_click()
      view |> element("[data-testid=release-apply]") |> render_click()
      view |> element("[data-testid=release-confirm-apply]") |> render_click()

      assert text(c).code =~ "v3"

      assert %DefinitionApply{action: :replaced, previous: %{"code" => previous}} =
               Repo.one(from(a in DefinitionApply, order_by: [desc: a.id], limit: 1))

      assert previous =~ "here"
    end

    test "keeping the version here records it, and it no longer waits", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, @path)
      view |> element("[data-testid=release-row][data-uid=#{c.text_module.uid}]") |> render_click()
      view |> element("[data-testid=release-choice-here]") |> render_click()
      view |> element("[data-testid=release-apply]") |> render_click()
      view |> element("[data-testid=release-confirm-apply]") |> render_click()

      assert text(c).code =~ "here"
      refute has_element?(view, "[data-testid=release-row][data-uid=#{c.text_module.uid}]")
    end
  end

  test "a definition never applied from files needs Replace", %{conn: conn} = c do
    text(c) |> Changeset.change(class: "made-here") |> Repo.update!()
    Repo.delete_all(from(a in DefinitionApply, where: a.uid == ^c.text_module.uid))

    {:ok, view, _html} = live(conn, @path)
    view |> element("[data-testid=release-row][data-uid=#{c.text_module.uid}]") |> render_click()
    assert render(view) =~ "Never applied from the release"
    view |> element("[data-testid=release-replace]") |> render_click()
    view |> element("[data-testid=release-apply]") |> render_click()
    view |> element("[data-testid=release-confirm-apply]") |> render_click()

    assert text(c).class == "class"
    assert %DefinitionApply{action: :replaced} = Repo.one(from(a in DefinitionApply, order_by: [desc: a.id], limit: 1))
  end

  # brandocms/brando#3541
  test "an invalid release file is named, with each problem on its own line", %{conn: conn} = c do
    [file] = c.path |> Path.join("content/text.exs") |> Path.wildcard()
    source = File.read!(file)
    broken = String.replace(source, "multi false", ~s(multi "often"))
    refute broken == source
    File.write!(file, broken)

    {:ok, view, _html} = live(conn, @path)

    lines =
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query(".release-notice.is-error .release-notice-text p")
      |> Enum.map(&LazyHTML.text/1)

    assert lines == [~s|content/text.exs: multi must be true or false (got "often")|]
  end

  test "only superusers, without groups", %{conn: conn} do
    admin = Factory.insert(:random_user, role: :admin)
    conn = Brando.Test.log_in_user(conn, admin)
    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, @path)
  end

  test "with groups, entries the person may not read are not listed", c do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()
    scope = Brando.Authorization.Scope.standalone(c.user)
    applier = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})

    {:ok, group} =
      Brando.Authorization.Groups.create(scope, %{name: "Appliers"}, [
        "brando.admin.access",
        "brando.module_definitions.apply"
      ])

    {:ok, :ok} = Brando.Authorization.Groups.add_member(scope, group.id, applier.id)
    release_template!(c, "text", "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")

    conn = Brando.Test.log_in_user(Brando.Test.Support.admin_conn(), applier)
    {:ok, view, _html} = live(conn, @path)
    view |> element("[data-testid=release-row][data-uid=#{c.text_module.uid}]") |> render_click()
    view |> element("[data-testid=release-tab-entries]") |> render_click()
    refute has_element?(view, "[data-testid=release-entry]")
  end

  test "with groups, a member granted brando.module_definitions.apply may apply release code", c do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()
    scope = Brando.Authorization.Scope.standalone(c.user)
    editor = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    assert {:error, :forbidden} = Release.authorize(editor)

    {:ok, group} =
      Brando.Authorization.Groups.create(scope, %{name: "Release appliers"}, [
        "brando.admin.access",
        "brando.module_definitions.apply"
      ])

    {:ok, :ok} = Brando.Authorization.Groups.add_member(scope, group.id, editor.id)
    assert :ok = Release.authorize(editor)

    release_template!(c, "text", "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")
    assert {:ok, %{batch_id: batch_id}} = Release.apply([c.text_module.uid], user: editor.id, wait: false)
    assert text(c).code =~ "v2"
    assert Batches.get(batch_id).applied_by_id == editor.id
  end
end

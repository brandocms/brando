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
      # The template changed: the container's other fields have no diff yet
      refute has_element?(view, "#def-#{container.uid}")
      assert has_element?(view, "[data-testid=release-tab-entries]")
      refute has_element?(view, "[data-testid=release-tab-preview]")

      view |> element("[data-testid=release-apply]") |> render_click()
      view |> element("[data-testid=release-confirm-apply]") |> render_click()

      assert Repo.get!(Brando.Content.Container, container.id).code =~ "from-release"
      assert [%{hex_value: "#fafafa"}] = Repo.get!(Brando.Content.Palette, palette.id).colors
      assert Batches.pending().definitions["items"] |> Enum.map(& &1["kind"]) |> Enum.sort() == ["container", "palette"]
    end)
  end

  test "a container whose template and palette both change shows both diffs", %{conn: conn} = c do
    palette = fn key ->
      {:ok, palette} =
        Brando.Content.create_palette(
          %{"name" => key, "namespace" => "site", "key" => key, "status" => "published", "colors" => []},
          c.user
        )

      palette
    end

    {paper, night} = {palette.("paper"), palette.("night")}

    {:ok, container} =
      Brando.Content.create_container(
        %{
          "name" => "Tinted",
          "namespace" => "Sections",
          "code" => "<section>{{ content }}</section>",
          "type" => "liquid",
          "palette_id" => paper.id
        },
        c.user
      )

    styles = c.path <> "-styles"
    {:ok, _} = Definitions.export(styles, c.user)
    on_exit(fn -> File.rm_rf!(styles) end)
    for dir <- ~w(palettes containers), do: File.cp_r!(Path.join(styles, dir), Path.join(c.path, dir))
    {:ok, _} = Release.plan(user: c.user.id, version: "1.0.0")
    File.write!(Path.join(c.path, "containers/tinted.liquid"), "<aside>{{ content }}</aside>")
    file = Path.join(c.path, "containers/tinted.exs")
    File.write!(file, String.replace(File.read!(file), ~s(palette "#{paper.uid}"), ~s(palette "#{night.uid}")))

    manual(fn ->
      {:ok, view, _html} = live(conn, @path)
      view |> element("[data-testid=release-row][data-uid='#{container.uid}']") |> render_click()
      assert has_element?(view, "#tpl-#{container.uid}")
      assert view |> element("#def-#{container.uid}") |> render() =~ night.uid
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

      # The open row's module and count were loaded with it: a render for
      # another reason does not query them again
      test_pid = self()
      handler = "release-detail-queries-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler,
        [:brando_integration, :repo, :query],
        fn _event, _measurements, meta, _config ->
          if self() == view.pid and meta.source in ["content_modules", "content_blocks"],
            do: send(test_pid, {:detail_query, meta.source})
        end,
        nil
      )

      try do
        view |> element("[data-testid=release-tab-entries]") |> render_click()
        view |> element("[data-testid=release-tab-template]") |> render_click()
        refute_received {:detail_query, _}
      after
        :telemetry.detach(handler)
      end
    end)
  end

  describe "blocks that hold values their module no longer defines" do
    # A block of `module` on an older version, holding a var `key`
    defp stale_block!(c, module, key) do
      block =
        Repo.insert!(%Brando.Content.Block{
          uid: Brando.Utils.generate_uid(),
          type: :module,
          module_id: module.id,
          creator_id: c.user.id
        })

      Repo.insert!(%Brando.Content.Var{block_id: block.id, key: key, type: :boolean, label: %{"en" => key}})
      block
    end

    # The release no longer defines the Case module's `wide` var
    defp remove_wide!(c) do
      exs = Path.join(c.path, "content/case.exs")
      source = File.read!(exs)
      without = Regex.replace(~r/\n    var "wide", "boolean" do\n.*?\n    end\n/s, source, "\n")
      assert without != source
      File.write!(exs, without)
    end

    defp apply_all(view) do
      view |> element("[data-testid=release-apply]") |> render_click()
      view |> element("[data-testid=release-confirm-apply]") |> render_click()
      Oban.drain_queue(queue: :default)
      send(view.pid, :tick)
      eventually(view, &(&1 =~ "release-banner is-done"))
    end

    defp resolve_path(module), do: "/admin/config/content/modules/update/#{module.id}/stale-blocks"

    test "the applied banner counts them and links to the module's Resolve blocks; after Keep the notice stays until they are resolved",
         %{conn: conn} = c do
      stale_block!(c, c.case_module, "wide")
      remove_wide!(c)

      manual(fn ->
        {:ok, view, _html} = live(conn, @path)
        # The release still waits: the module defines the var
        refute has_element?(view, "[data-testid=release-leftovers]")

        apply_all(view)
        assert has_element?(view, "[data-testid=release-banner-leftovers]", "1 block")
        assert has_element?(view, ~s([data-testid=release-banner-resolve][href="#{resolve_path(c.case_module)}"]))
        # The banner names them: the notice above the review does not again
        refute has_element?(view, "[data-testid=release-leftovers]")

        view |> element("[data-testid=release-keep]") |> render_click()
        assert has_element?(view, "[data-testid=release-nothing]")
        assert has_element?(view, ~s([data-testid=release-leftovers-resolve][href="#{resolve_path(c.case_module)}"]))

        {:ok, _} = Brando.Content.StaleBlocks.apply(case_module(c), %{{:var, "wide"} => :drop}, c.user)
        {:ok, view, _html} = live(conn, @path)
        refute has_element?(view, "[data-testid=release-leftovers]")
      end)
    end

    test "the applied banner names none when the apply left none", %{conn: conn} = c do
      release_template!(c, "text", "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")

      manual(fn ->
        {:ok, view, _html} = live(conn, @path)
        apply_all(view)
        refute has_element?(view, "[data-testid=release-banner-leftovers]")
        refute has_element?(view, "[data-testid=release-banner-resolve]")
      end)
    end

    test "the applied banner links to the list when several applied modules have them", %{conn: conn} = c do
      stale_block!(c, c.case_module, "wide")
      stale_block!(c, c.text_module, "gone")
      remove_wide!(c)
      release_template!(c, "text", "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}")

      manual(fn ->
        {:ok, view, _html} = live(conn, @path)
        apply_all(view)
        assert has_element?(view, "[data-testid=release-banner-leftovers]", "2 blocks")

        assert has_element?(
                 view,
                 ~s([data-testid=release-banner-resolve][href="/admin/config/content/modules/stale-blocks"])
               )
      end)
    end

    test "the notice shows while changes wait, and a block only on an older version does not count",
         %{conn: conn} = c do
      stale_block!(c, c.text_module, "gone")
      # Behind, but holding only what the module defines
      stale_block!(c, c.case_module, "wide")
      release_template!(c, "case", "<div class=\"case v2\">{{ heading }}</div>")

      {:ok, view, _html} = live(conn, @path)
      assert has_element?(view, "[data-testid=release-row][data-uid=#{c.case_module.uid}]")
      assert has_element?(view, ~s([data-testid=release-leftovers-resolve][href="#{resolve_path(c.text_module)}"]))
    end
  end

  describe "dropping leftovers in the apply" do
    defp wide(block), do: Repo.get_by(Brando.Content.Var, block_id: block.id, key: "wide")
    defp drop_box(view), do: element(view, "[data-testid=release-drop]")

    test "the dialog has no box when no block holds a removed ref or var", %{conn: conn} = c do
      remove_wide!(c)
      {:ok, view, _html} = live(conn, @path)
      view |> element("[data-testid=release-apply]") |> render_click()
      refute has_element?(view, "[data-testid=release-drop]")
      refute has_element?(view, "[data-testid=release-confirm-drop]")
    end

    test "ticked, the apply drops the values, the banner says so, and Revert puts them back", %{conn: conn} = c do
      block = stale_block!(c, c.case_module, "wide")
      remove_wide!(c)

      manual(fn ->
        {:ok, view, _html} = live(conn, @path)
        view |> element("[data-testid=release-apply]") |> render_click()
        refute has_element?(view, "[data-testid=release-drop][checked]")
        assert has_element?(view, "[data-testid=release-confirm-drop]", "1 block")

        view |> drop_box() |> render_click()
        assert has_element?(view, "[data-testid=release-drop][checked]")
        view |> element("[data-testid=release-confirm-apply]") |> render_click()
        assert wide(block) == nil

        Oban.drain_queue(queue: :default)
        send(view.pid, :tick)
        eventually(view, &(&1 =~ "release-banner is-done"))
        assert has_element?(view, "[data-testid=release-banner-dropped]", "1 block")
        refute has_element?(view, "[data-testid=release-banner-leftovers]")

        view |> element("[data-testid=release-revert]") |> render_click()
        refute has_element?(view, "[data-testid=release-banner]")
        assert wide(block)
      end)
    end

    test "starts unticked each time the dialog opens", %{conn: conn} = c do
      stale_block!(c, c.case_module, "wide")
      remove_wide!(c)

      {:ok, view, _html} = live(conn, @path)
      view |> element("[data-testid=release-apply]") |> render_click()
      view |> drop_box() |> render_click()
      assert has_element?(view, "[data-testid=release-drop][checked]")

      view |> element("#release-confirm [phx-click=close_confirm]") |> render_click()
      view |> element("[data-testid=release-apply]") |> render_click()
      refute has_element?(view, "[data-testid=release-drop][checked]")

      # Unticked, the apply leaves them
      view |> element("[data-testid=release-confirm-apply]") |> render_click()
      assert Brando.Content.StaleBlocks.count_with_leftovers(case_module(c)) == 1
    end

    test "the dialog names the refs and vars the drop covers, per module", %{conn: conn} = c do
      stale_block!(c, c.case_module, "wide")
      remove_wide!(c)

      {:ok, view, _html} = live(conn, @path)
      view |> element("[data-testid=release-apply]") |> render_click()
      assert has_element?(view, ~s([data-testid=release-drop-keys][data-uid="#{c.case_module.uid}"] code), "wide")
    end

    test "refused because the removals changed, the dialog plans the drop again, unticked", %{conn: conn} = c do
      block = stale_block!(c, c.case_module, "wide")
      remove_wide!(c)

      {:ok, view, _html} = live(conn, @path)
      view |> element("[data-testid=release-apply]") |> render_click()
      view |> drop_box() |> render_click()
      Repo.delete!(wide(block))

      view |> element("[data-testid=release-confirm-apply]") |> render_click()
      assert has_element?(view, "#release-confirm[data-open=true] .release-confirm-warning")
      refute Batches.pending()
      # Nothing is held any more: no box, and the apply goes through
      refute has_element?(view, "[data-testid=release-drop]")
      view |> element("[data-testid=release-confirm-apply]") |> render_click()
      assert Batches.pending()
    end

    test "a removed ref whose slot holds footnotes says why it stays", %{conn: conn} = c do
      block =
        Repo.insert!(%Brando.Content.Block{
          uid: Brando.Utils.generate_uid(),
          type: :module,
          module_id: c.case_module.id,
          creator_id: c.user.id
        })

      Repo.insert!(%Brando.Content.Ref{
        block_id: block.id,
        name: "cover",
        uid: Brando.Utils.generate_uid(),
        data: %Brando.Villain.Blocks.PictureBlock{type: "picture", data: %Brando.Villain.Blocks.PictureBlock.Data{}}
      })

      Repo.insert!(%Brando.Content.Block{
        uid: Brando.Utils.generate_uid(),
        type: :slot,
        slot_kind: :footnote,
        slot_name: "cover",
        parent_id: block.id
      })

      exs = Path.join(c.path, "content/case.exs")
      source = File.read!(exs)
      without = Regex.replace(~r/\n    ref "cover", "picture" do\n.*?\n    end\n/s, source, "\n")
      assert without != source
      File.write!(exs, without)

      {:ok, view, _html} = live(conn, @path)
      view |> element("[data-testid=release-apply]") |> render_click()
      assert has_element?(view, "[data-testid=release-drop-slotted]")
      refute has_element?(view, "[data-testid=release-drop]")
    end

    test "over the limit, the box is disabled with the reason", %{conn: conn} = c do
      hold_wide_over_the_limit!(c)
      remove_wide!(c)
      {:ok, view, _html} = live(conn, @path)
      view |> element("[data-testid=release-apply]") |> render_click()
      assert has_element?(view, "[data-testid=release-drop][disabled]")
      assert has_element?(view, "[data-testid=release-drop-limit]", "1500 blocks")
    end

    test "refused because editors pushed the drop over the limit, the box is unticked and disabled", %{conn: conn} = c do
      stale_block!(c, c.case_module, "wide")
      remove_wide!(c)

      {:ok, view, _html} = live(conn, @path)
      view |> element("[data-testid=release-apply]") |> render_click()
      view |> drop_box() |> render_click()
      assert has_element?(view, "[data-testid=release-drop][checked]")
      hold_wide_over_the_limit!(c)

      view |> element("[data-testid=release-confirm-apply]") |> render_click()
      assert has_element?(view, "#release-confirm[data-open=true] .release-confirm-warning")
      refute Batches.pending()
      assert has_element?(view, "[data-testid=release-drop][disabled]")
      refute has_element?(view, "[data-testid=release-drop][checked]")
      assert has_element?(view, "[data-testid=release-drop-limit]")
    end

    # More blocks holding the removed var than one apply drops
    defp hold_wide_over_the_limit!(c) do
      now = NaiveDateTime.utc_now(:second)

      blocks =
        for _ <- 1..1501,
            do: %{
              uid: Brando.Utils.generate_uid(),
              type: :module,
              module_id: c.case_module.id,
              inserted_at: now,
              updated_at: now
            }

      {_, ids} = Repo.insert_all(Brando.Content.Block, blocks, returning: [:id])

      Repo.insert_all(
        Brando.Content.Var,
        for(
          %{id: id} <- ids,
          do: %{block_id: id, key: "wide", type: :boolean, label: %{"en" => "Wide"}, inserted_at: now, updated_at: now}
        )
      )
    end
  end

  describe "a renamed var" do
    setup c do
      block =
        Repo.insert!(%Brando.Content.Block{
          uid: Brando.Utils.generate_uid(),
          type: :module,
          module_id: c.case_module.id,
          creator_id: c.user.id
        })

      Repo.insert!(%Brando.Content.Var{
        block_id: block.id,
        key: "wide",
        type: :boolean,
        label: %{"en" => "Wide"},
        value_boolean: true
      })

      exs = Path.join(c.path, "content/case.exs")
      source = File.read!(exs)

      renamed =
        String.replace(source, ~s(var "wide", "boolean" do\n), ~s(var "full", "boolean" do\n      renamed_from "wide"\n))

      assert renamed != source
      File.write!(exs, renamed)
      %{block: block, exs: exs}
    end

    test "lists the move under Ready to apply, and the apply moves the value", %{conn: conn} = c do
      manual(fn ->
        {:ok, view, _html} = live(conn, @path)
        view |> element("[data-testid=release-row][data-uid=#{c.case_module.uid}]") |> render_click()
        assert has_element?(view, "[data-testid=release-moves] li[data-uid=#{c.case_module.uid}]", "wide → full")
        refute has_element?(view, "[data-testid=release-removals]")

        view |> element("[data-testid=release-apply]") |> render_click()
        view |> element("[data-testid=release-confirm-apply]") |> render_click()
        assert %{value_boolean: true} = Repo.get_by(Brando.Content.Var, block_id: c.block.id, key: "full")
        refute Repo.get_by(Brando.Content.Var, block_id: c.block.id, key: "wide")
      end)
    end

    test "in a conflict, says the values move and the apply can't be reverted once the release's version is chosen",
         %{conn: conn} = c do
      case_module(c) |> Changeset.change(code: case_module(c).code <> "<!-- here -->") |> Repo.update!()

      manual(fn ->
        {:ok, view, _html} = live(conn, @path)
        view |> element("[data-testid=release-row][data-uid=#{c.case_module.uid}]") |> render_click()
        assert has_element?(view, "[data-testid=release-choices]")
        refute has_element?(view, "[data-testid=release-moves]")

        view |> element("[data-testid=release-choice-release]") |> render_click()
        assert has_element?(view, "[data-testid=release-moves] li[data-uid=#{c.case_module.uid}]", "wide → full")

        view |> element("[data-testid=release-apply]") |> render_click()
        view |> element("[data-testid=release-confirm-apply]") |> render_click()
        assert %{value_boolean: true} = Repo.get_by(Brando.Content.Var, block_id: c.block.id, key: "full")
      end)
    end

    test "in a conflict whose moves are refused, shows the refusal, not the moves, once the release's version is chosen",
         %{conn: conn} = c do
      # The block holds a value of its own under the new key: the move is refused
      Repo.insert!(%Brando.Content.Var{
        block_id: c.block.id,
        key: "full",
        type: :boolean,
        label: %{"en" => "Full"},
        value_boolean: true
      })

      case_module(c) |> Changeset.change(code: case_module(c).code <> "<!-- here -->") |> Repo.update!()

      {:ok, view, _html} = live(conn, @path)
      view |> element("[data-testid=release-row][data-uid=#{c.case_module.uid}]") |> render_click()
      view |> element("[data-testid=release-choice-release]") |> render_click()

      refute has_element?(view, "[data-testid=release-moves]")
      assert has_element?(view, "[data-testid=release-move-refusals] li[data-uid=#{c.case_module.uid}]", "wide")
    end

    test "over the apply's limit, lists the values left for the command, which the applied row shows too",
         %{conn: conn} = c do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      {_, blocks} =
        Repo.insert_all(
          Brando.Content.Block,
          for(
            _ <- 1..1500,
            do: %{
              uid: Brando.Utils.generate_uid(),
              type: :module,
              module_id: c.case_module.id,
              module_origin: :local,
              creator_id: c.user.id,
              inserted_at: now,
              updated_at: now
            }
          ),
          returning: [:id]
        )

      Repo.insert_all(
        Brando.Content.Var,
        for(
          %{id: id} <- blocks,
          do: %{block_id: id, key: "wide", type: :boolean, label: %{"en" => "Wide"}, inserted_at: now, updated_at: now}
        )
      )

      command = "mix brando.modules resolve --uid #{c.case_module.uid} --user #{c.user.id} --map var:wide=full --apply"

      manual(fn ->
        {:ok, view, _html} = live(conn, @path)
        view |> element("[data-testid=release-row][data-uid=#{c.case_module.uid}]") |> render_click()
        refute has_element?(view, "[data-testid=release-moves]")
        assert has_element?(view, "[data-testid=release-left-moves] li[data-uid=#{c.case_module.uid}]", "wide → full")
        assert has_element?(view, "[data-testid=release-left-moves] code", command)

        view |> element("[data-testid=release-apply]") |> render_click()
        view |> element("[data-testid=release-confirm-apply]") |> render_click()
        assert %{value_boolean: true} = Repo.get_by(Brando.Content.Var, block_id: c.block.id, key: "wide")

        view |> element("[data-testid=release-applied-row][data-uid=#{c.case_module.uid}]") |> render_click()
        assert has_element?(view, "[data-testid=release-move-command]", command)
      end)
    end

    test "is refused at apply when the files' renames changed after the review", %{conn: conn} = c do
      manual(fn ->
        {:ok, view, _html} = live(conn, @path)
        view |> element("[data-testid=release-row][data-uid=#{c.case_module.uid}]") |> render_click()
        view |> element("[data-testid=release-apply]") |> render_click()

        File.write!(c.exs, String.replace(File.read!(c.exs), ~s(\n      renamed_from "wide"), ""))
        view |> element("[data-testid=release-confirm-apply]") |> render_click()

        assert render(view) =~ "review it again"
        assert Repo.get_by(Brando.Content.Var, block_id: c.block.id, key: "wide")
        assert [_ | _] = Repo.preload(case_module(c), :vars).vars |> Enum.filter(&(&1.key == "wide"))
      end)
    end
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

    test "kept here with an apply, both are recorded", %{conn: conn} = c do
      release_template!(c, "case", "<div class=\"case v2\">{{ heading }}</div>")

      manual(fn ->
        {:ok, view, _html} = live(conn, @path)
        keep_text_here_and_confirm(view, c)
        view |> element("[data-testid=release-confirm-apply]") |> render_click()

        assert case_module(c).code =~ "v2"
        assert text(c).code =~ "here"
        assert %DefinitionApply{action: :kept} = latest_apply(c.text_module.uid)
        assert [%{"uid" => uid}] = Batches.pending().definitions["items"]
        assert uid == c.case_module.uid
        refute has_element?(view, "#release-confirm[data-open=true]")
        refute has_element?(view, "[data-testid=release-row][data-uid=#{c.text_module.uid}]")
      end)
    end

    test "a refused apply keeps no version here: edited here since the dialog opened", %{conn: conn} = c do
      release_template!(c, "case", "<div class=\"case v2\">{{ heading }}</div>")

      assert_refused_keeps_nothing(conn, c, fn ->
        case_module(c) |> Changeset.change(code: case_module(c).code <> "<!-- here -->") |> Repo.update!()
      end)
    end

    test "a refused apply keeps no version here: the removals changed", %{conn: conn} = c do
      block = stale_block!(c, c.case_module, "wide")
      remove_wide!(c)

      assert_refused_keeps_nothing(conn, c, fn -> Repo.delete!(wide(block)) end, drop?: true)
    end

    test "a refused apply keeps no version here: the drop went over the limit", %{conn: conn} = c do
      stale_block!(c, c.case_module, "wide")
      remove_wide!(c)

      assert_refused_keeps_nothing(conn, c, fn -> hold_wide_over_the_limit!(c) end, drop?: true)
    end

    test "a refused apply keeps no version here: the renames changed", %{conn: conn} = c do
      block = stale_block!(c, c.case_module, "wide")
      exs = Path.join(c.path, "content/case.exs")
      source = File.read!(exs)

      renamed =
        String.replace(source, ~s(var "wide", "boolean" do\n), ~s(var "full", "boolean" do\n      renamed_from "wide"\n))

      assert renamed != source
      File.write!(exs, renamed)

      assert_refused_keeps_nothing(conn, c, fn ->
        File.write!(exs, String.replace(renamed, ~s(\n      renamed_from "wide"), ""))
      end)

      assert wide(block)
    end

    test "a later version kept here that is refused leaves the earlier ones unkept", %{conn: conn} = c do
      # The Case module in conflict too; its row comes before the Text module's
      release_template!(c, "case", "<div class=\"case v2\">{{ heading }}</div>")
      {:ok, _} = Release.apply([c.case_module.uid], user: c.user.id, wait: false)
      {:ok, _} = Batches.keep(Batches.pending(), c.user)
      case_module(c) |> Changeset.change(code: "<div class=\"case here\">{{ heading }}</div>") |> Repo.update!()
      release_template!(c, "case", "<div class=\"case v3\">{{ heading }}</div>")

      {:ok, view, _html} = live(conn, @path)
      before = apply_rows()

      for uid <- [c.case_module.uid, c.text_module.uid] do
        view |> element("[data-testid=release-row][data-uid=#{uid}]") |> render_click()
        view |> element("[data-testid=release-choice-here]") |> render_click()
      end

      view |> element("[data-testid=release-apply]") |> render_click()
      # The Text module's edit is undone elsewhere: it is no longer in conflict
      text(c) |> Changeset.change(code: "<p class=\"v2\">{{ heading }}</p>{% ref refs.body %}") |> Repo.update!()
      view |> element("[data-testid=release-confirm-apply]") |> render_click()

      assert has_element?(view, "#release-confirm[data-open=true] .release-confirm-warning")
      assert apply_rows() == before
      assert c.case_module.uid in conflicts(c)
    end
  end

  defp keep_text_here_and_confirm(view, c) do
    view |> element("[data-testid=release-row][data-uid=#{c.text_module.uid}]") |> render_click()
    view |> element("[data-testid=release-choice-here]") |> render_click()
    view |> element("[data-testid=release-apply]") |> render_click()
  end

  # The "keep here" choice and an apply refused because of what `change`
  # does after the dialog opened: no version is kept, and the conflicts are
  # those before the click
  defp assert_refused_keeps_nothing(conn, c, change, opts \\ []) do
    manual(fn ->
      {:ok, view, _html} = live(conn, @path)
      keep_text_here_and_confirm(view, c)
      if opts[:drop?], do: view |> drop_box() |> render_click()
      change.()
      before = {apply_rows(), conflicts(c)}

      view |> element("[data-testid=release-confirm-apply]") |> render_click()

      assert has_element?(view, "#release-confirm[data-open=true] .release-confirm-warning")
      refute Batches.pending()
      assert {apply_rows(), conflicts(c)} == before
      assert c.text_module.uid in conflicts(c)
    end)
  end

  defp apply_rows, do: Repo.all(from(a in DefinitionApply, order_by: a.id, select: {a.id, a.uid, a.action}))

  defp latest_apply(uid),
    do: Repo.one(from(a in DefinitionApply, where: a.uid == ^uid, order_by: [desc: a.id], limit: 1))

  defp conflicts(c) do
    {:ok, report} = Release.plan(user: c.user.id, adopt: false)
    for item <- report.items, item.action == :conflict, do: item.uid
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

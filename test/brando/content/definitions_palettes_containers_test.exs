defmodule Brando.Content.DefinitionsPalettesContainersTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.{Container, Definitions, Module, Palette}
  alias Brando.Content.Definition.{Plan, Snapshot}
  alias Brando.{Factory, Repo, Tenant}

  import Ecto.Query, only: [from: 2]

  @fixtures "test/fixtures/definitions/styles"

  setup do
    user = Factory.insert(:random_user)
    path = Path.join(System.tmp_dir!(), "brando-styles-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    %{user: user, path: path}
  end

  defp fixtures!(path, names) do
    for name <- names, do: File.cp!(Path.join(@fixtures, name <> ".exs.txt"), Path.join(path, name <> ".exs"))
    path
  end

  defp palette!(user, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          "name" => "Paper",
          "namespace" => "site",
          "key" => "paper",
          "global" => true,
          "instructions" => "For quiet sections",
          "status" => "published",
          "colors" => [
            %{"name" => "Background", "key" => "background", "hex_value" => "#fff9f4", "instructions" => "Behind"},
            %{"name" => "Text", "key" => "foreground", "hex_value" => "#000000"}
          ]
        },
        attrs
      )

    {:ok, palette} = Brando.Content.create_palette(params, user)
    palette
  end

  defp container!(user, palette, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          "name" => "Tinted section",
          "namespace" => "Sections",
          "code" => ~s(<section b-section="site-paper">{{ content }}</section>),
          "type" => "liquid",
          "allow_custom_palette" => true,
          "palette_namespace" => "site",
          "palette_id" => palette && palette.id
        },
        attrs
      )

    {:ok, container} = Brando.Content.create_container(params, user)
    container
  end

  describe "files" do
    test "a palette and a container read into definitions; the container names its palette by uid", c do
      assert {:ok, bundle} = Definitions.read(fixtures!(c.path, ~w(paper tinted)))

      assert [
               %{
                 "kind" => "palette",
                 "uid" => "acme-palette-paper",
                 "name" => "Paper",
                 "namespace" => "site",
                 "key" => "paper",
                 "global" => false,
                 "instructions" => nil,
                 "colors" => [
                   %{"key" => "background", "hex_value" => "#fff9f4", "name" => "Background"} = background,
                   %{"key" => "foreground", "name" => "Text", "instructions" => nil}
                 ]
               }
             ] = bundle["palettes"]

      assert background["instructions"] == "Behind the text"

      assert [
               %{
                 "kind" => "container",
                 "uid" => "acme-container-tinted",
                 "namespace" => "Sections",
                 "type" => "liquid",
                 "code" => ~s(<section b-section="site-paper">{{ content }}</section>),
                 "allow_custom_palette" => false,
                 "palette" => "acme-palette-paper"
               }
             ] = bundle["containers"]

      assert bundle["modules"] == [] and bundle["table_templates"] == []
    end

    test "a container may name its palette by the palette's module name", c do
      fixtures!(c.path, ~w(paper))

      File.write!(Path.join(c.path, "tinted.exs"), """
      defmodule MySite.Tinted do
        use Brando.Content.Definition
        kind :container
        uid "tinted"
        name "Tinted"
        namespace "Sections"
        palette MySite.Definitions.Palettes.Paper
        template :liquid, "{{ content }}"
      end
      """)

      assert {:ok, %{"containers" => [%{"palette" => "acme-palette-paper"}]}} = Definitions.read(c.path)
    end

    test "each kind declares only what it holds, and a palette's names are what the schema stores", c do
      cases = [
        {~s(kind :palette\n  uid "p"\n  name "P"\n  key "p"\n  template :liquid, "x"),
         "palette definitions don't declare a template"},
        {~s(kind :palette\n  uid "p"\n  name "P"\n  key "p"\n  class "x"), "unsupported palette options [:class]"},
        {~s(kind :container\n  uid "c"\n  name "C"\n  namespace "N"\n  colors do\n    color :a, "#000000"\n  end\n  template :liquid, "x"),
         "container definitions don't declare colors"},
        {~s(uid "m"\n  name "M"\n  key "k"\n  template :liquid, "x"), "unsupported module options [:key]"},
        {~s(kind :palette\n  uid "p"\n  name en: "P"\n  key "p"), "name"},
        {~s(kind :palette\n  uid "p"\n  name "P"\n  key "not a css name"), "key"},
        {~s(kind :palette\n  uid "p"\n  name "P"\n  key "p"\n  colors do\n    color :a, "#000000" do\n      name "A"\n    end\n    color :a, "#ffffff" do\n      name "B"\n    end\n  end),
         "color keys"}
      ]

      for {body, expected} <- cases do
        File.write!(Path.join(c.path, "one.exs"), "defmodule One do\n  use Brando.Content.Definition\n  #{body}\nend\n")
        assert {:error, message} = Definitions.read(c.path)
        assert message =~ expected
      end
    end

    test "compiled definitions build the same bundle as their files", c do
      assert {:ok, read} = Definitions.read(fixtures!(c.path, ~w(paper tinted)))

      [{palette, _}] = Code.compile_file(Path.join(c.path, "paper.exs"))
      [{container, _}] = Code.compile_file(Path.join(c.path, "tinted.exs"))

      assert {:ok, compiled} = Definitions.from_modules([palette, container], root: c.path)
      assert compiled["palettes"] == read["palettes"]
      assert compiled["containers"] == read["containers"]
    end
  end

  describe "export" do
    test "writes every local palette and container, which read back as exported", c do
      palette = palette!(c.user)
      container = container!(c.user, palette)
      # A shared-library override is the library's, and stays out
      palette!(c.user, %{"key" => "override", "name" => "Override"})
      |> Ecto.Changeset.change(source_palette_id: 999_999)
      |> Repo.update!()

      assert {:ok, exported} = Definitions.export(Path.join(c.path, "out"), c.user)
      assert "palettes/paper.exs" in exported.files
      assert "containers/tinted-section.exs" in exported.files
      assert "containers/tinted-section.liquid" in exported.files
      assert [%{"uid" => uid, "colors" => [_, _], "global" => true}] = exported.bundle["palettes"]
      assert uid == palette.uid

      assert [%{"uid" => container_uid, "palette" => ^uid, "allow_custom_palette" => true}] =
               exported.bundle["containers"]

      assert container_uid == container.uid

      source = File.read!(Path.join(exported.directory, "palettes/paper.exs"))
      assert source =~ "kind :palette"
      assert source =~ ~s(color "background", "#fff9f4" do)

      assert File.read!(Path.join(exported.directory, "containers/tinted-section.liquid")) == container.code

      assert {:ok, read} = Definitions.read(exported.directory)
      assert Map.take(read, ~w(palettes containers)) == Map.take(exported.bundle, ~w(palettes containers))
      assert read["baseline"]["palettes"][uid] == exported.bundle["baseline"]["palettes"][uid]
    end

    test "selecting a container brings the palette it names", c do
      palette = palette!(c.user)
      container = container!(c.user, palette)
      palette!(c.user, %{"key" => "other", "name" => "Other"})

      assert {:ok, exported} = Definitions.export(Path.join(c.path, "out"), c.user, uids: [container.uid])
      assert Enum.map(exported.bundle["palettes"], & &1["uid"]) == [palette.uid]
      assert exported.bundle["modules"] == []
    end

    test "a palette or container saved in the admin gets a uid of its own, and so does its copy", c do
      palette = palette!(c.user)
      container = container!(c.user, palette)
      assert is_binary(palette.uid) and is_binary(container.uid)

      assert {:ok, copy} = Brando.Content.duplicate_palette(palette.id, c.user)
      assert copy.uid != palette.uid
      assert {:ok, copy} = Brando.Content.duplicate_container(container.id, c.user)
      assert copy.uid != container.uid
      assert Repo.aggregate(Palette, :count) == 2 and Repo.aggregate(Container, :count) == 2
    end
  end

  defp import!(bundle, user, opts \\ []) do
    assert {:ok, plan} = Definitions.plan(bundle, user, opts)
    assert Plan.applicable?(plan), inspect(Enum.map(plan.items, &{&1.uid, &1.action, &1.reason}))
    assert {:ok, result} = Definitions.apply(plan, user)
    result
  end

  defp read!(path) do
    assert {:ok, bundle} = Definitions.read(path)
    bundle
  end

  defp css, do: Phoenix.HTML.safe_to_string(Brando.Cache.Palettes.get_css())

  defp actions(plan), do: plan.items |> Map.new(&{&1.uid, &1.action})

  defp paper, do: Repo.get_by!(Palette, uid: "acme-palette-paper")
  defp tinted, do: Repo.get_by!(Container, uid: "acme-container-tinted")

  defp swatches(palette), do: Enum.map(palette.colors, &Map.take(&1, [:key, :name, :hex_value, :instructions]))

  defp export!(c, name \\ "out", opts \\ []) do
    assert {:ok, exported} = Definitions.export(Path.join(c.path, name), c.user, opts)
    assert {:ok, bundle} = Definitions.read(exported.directory)
    bundle
  end

  describe "import" do
    test "files into an empty database create the palette, then the container; a second import is a noop", c do
      assert {:ok, bundle} = Definitions.read(fixtures!(c.path, ~w(paper tinted)))
      assert {:ok, plan} = Definitions.plan(bundle, c.user)
      assert actions(plan) == %{"acme-palette-paper" => :create, "acme-container-tinted" => :create}
      assert Repo.aggregate(Palette, :count) == 0

      assert {:ok, %{changes: changes}} = Definitions.apply(plan, c.user)
      assert Enum.map(changes, & &1.kind) == ["palette", "container"]
      assert tinted().palette_id == paper().id
      assert paper().status == :published

      exported = export!(c)
      assert {:ok, plan} = Definitions.plan(exported, c.user)
      assert Enum.all?(plan.items, &(&1.action == :noop))
      assert {:ok, %{changes: []}} = Definitions.apply(plan, c.user)
    end

    test "an edit in the admin after export makes the next import a conflict", c do
      import!(read!(fixtures!(c.path, ~w(paper tinted))), c.user)
      exported = export!(c)

      [_ | rest] = paper().colors
      colors = [%{name: "Background", key: "background", hex_value: "#eeeeee"} | Enum.map(rest, &Map.from_struct/1)]
      assert {:ok, _} = Brando.Content.update_palette(paper().id, %{colors: colors}, c.user)
      assert {:ok, _} = Brando.Content.update_container(tinted().id, %{code: "<div>{{ content }}</div>"}, c.user)

      edited =
        exported
        |> Map.update!("palettes", fn [p] -> [put_in(p, ["colors", Access.at(1), "hex_value"], "#111111")] end)
        |> Map.update!("containers", fn [t] -> [Map.put(t, "help_text", "Changed in the file")] end)

      assert {:ok, plan} = Definitions.plan(edited, c.user)

      assert actions(plan) == %{"acme-palette-paper" => :conflict, "acme-container-tinted" => :conflict}
      assert Enum.all?(plan.items, &(&1.reason == "target changed since export"))
    end

    test "a container whose palette is neither in the files nor here is refused, by name; one in the trash too", c do
      assert {:ok, bundle} = Definitions.read(fixtures!(c.path, ~w(tinted)))
      assert {:error, message} = Definitions.plan(bundle, c.user)
      assert message =~ ~s(container "acme-container-tinted")
      assert message =~ ~s(palette "acme-palette-paper" is neither in the files nor here)

      palette = palette!(c.user, %{"key" => "paper"})
      palette |> Ecto.Changeset.change(uid: "acme-palette-paper") |> Repo.update!()
      assert {:ok, plan} = Definitions.plan(bundle, c.user)
      assert actions(plan) == %{"acme-container-tinted" => :create}

      assert {:ok, _} = Brando.Content.delete_palette(palette.id, c.user)
      assert {:error, message} = Definitions.plan(bundle, c.user)
      assert message =~ "is neither in the files nor here"
    end

    test "an admin-made palette and container round-trip, and one hex value edited in the file changes only it", c do
      palette = palette!(c.user)
      container = container!(c.user, palette)
      css = css()
      picker = Container.get_palettes(nil, nil)
      exported = export!(c)

      import!(exported, c.user)
      assert Repo.get!(Palette, palette.id).updated_at == palette.updated_at
      assert swatches(Repo.get!(Palette, palette.id)) == swatches(palette)
      assert css() == css
      assert Container.get_palettes(nil, nil) == picker
      assert Repo.get!(Container, container.id).updated_at == container.updated_at

      path = Path.join([c.path, "out", "palettes", "paper.exs"])
      File.write!(path, String.replace(File.read!(path), "#fff9f4", "#fafafa"))
      assert {:ok, edited} = Definitions.read(Path.join(c.path, "out"))
      assert {:ok, plan} = Definitions.plan(edited, c.user)
      assert actions(plan) == %{palette.uid => :update, container.uid => :noop}
      assert {:ok, _} = Definitions.apply(plan, c.user)

      updated = Repo.get!(Palette, palette.id)
      assert [%{hex_value: "#fafafa", name: "Background", instructions: "Behind"}, second] = updated.colors
      assert second == hd(tl(palette.colors))
      assert Map.take(updated, [:global, :instructions, :status]) == Map.take(palette, [:global, :instructions, :status])
      assert css() =~ ~r/--palette-site-paper-background:\s*#fafafa/
      assert Repo.get!(Container, container.id).palette_id == palette.id
    end

    test "a module whose var names a palette of the bundle imports into an empty database", c do
      palette = palette!(c.user)
      write_module!(c.path, palette.uid)
      import!(read!(c.path), c.user)
      exported = export!(c, "out")
      assert [%{"vars" => [%{"assets" => %{"palette" => token}}]}] = exported["modules"]
      assert token == palette.uid
      assert exported["references"][token] == %{"kind" => "palette", "uid" => palette.uid}

      # Another database: nothing is here
      Repo.delete_all(Brando.Content.Var)
      Repo.delete_all(Module)
      Repo.delete_all(Palette)
      Repo.delete_all(Brando.Content.DefinitionApply)
      bundle = Map.put(exported, "source", "another-installation")

      import!(bundle, c.user)
      module = Repo.get_by!(Module, uid: "swatch") |> Repo.preload(:vars)
      assert [%{palette_id: palette_id}] = module.vars
      assert palette_id == Repo.get_by!(Palette, uid: palette.uid).id
    end

    test "a file written with a mapped palette id still imports", c do
      palette = palette!(c.user)
      write_module!(c.path, palette.uid)
      bundle = read!(c.path)

      legacy =
        bundle
        |> update_in(["modules", Access.at(0), "vars", Access.at(0), "assets"], &Map.put(&1, "palette", "palette:12"))
        |> Map.merge(%{"source" => "elsewhere", "references" => %{"palette:12" => %{"kind" => "palette", "id" => 12}}})

      assert {:error, message} = Definitions.plan(legacy, c.user)
      assert message =~ "requires a destination reference mapping"
      import!(legacy, c.user, references: %{"palette:12" => palette.id})
      assert [%{palette_id: id}] = Repo.get_by!(Module, uid: "swatch") |> Repo.preload(:vars) |> Map.fetch!(:vars)
      assert id == palette.id
    end

    test "a selective apply brings the palettes the module and the container name, refused by name in conflict", c do
      palette = palette!(c.user)
      container!(c.user, palette)
      write_module!(c.path, palette.uid)
      import!(read!(c.path), c.user)
      exported = export!(c, "out")

      assert {:ok, %{selection: selection}} = Definitions.plan(exported, c.user, select: [tinted_uid()])
      assert MapSet.equal?(selection, MapSet.new([tinted_uid(), palette.uid]))
      assert {:ok, %{selection: selection}} = Definitions.plan(exported, c.user, select: ["swatch"])
      assert MapSet.equal?(selection, MapSet.new(["swatch", palette.uid]))

      assert {:ok, _} = Brando.Content.update_palette(palette.id, %{name: "Edited here"}, c.user)
      edited = Map.update!(exported, "palettes", fn [p] -> [Map.put(p, "instructions", "In the file")] end)
      assert {:ok, plan} = Definitions.plan(edited, c.user, select: ["swatch"])
      refute Plan.applicable?(plan)
      assert %{action: :conflict} = Enum.find(plan.items, &(&1.uid == palette.uid))
    end

    test "the apply locks and rechecks palettes and containers: an edit or a trashed palette since planning is no overwrite",
         c do
      import!(read!(fixtures!(c.path, ~w(paper tinted))), c.user)
      exported = export!(c)
      edited = Map.update!(exported, "palettes", fn [p] -> [Map.put(p, "instructions", "From the file")] end)

      assert {:ok, plan} = Definitions.plan(edited, c.user)
      assert actions(plan)["acme-palette-paper"] == :update
      paper() |> Ecto.Changeset.change(name: "Edited meanwhile") |> Repo.update!()
      assert {:error, "target changed after planning; create a new plan"} = Definitions.apply(plan, c.user)
      assert paper().instructions == nil

      paper() |> Ecto.Changeset.change(name: "Paper") |> Repo.update!()
      assert {:ok, plan} = Definitions.plan(edited, c.user)
      assert {:ok, _} = Brando.Content.delete_palette(paper().id, c.user)
      assert {:error, _} = Definitions.apply(plan, c.user)
    end

    test "a shared-library override is neither exported nor imported over, and keeps its source", c do
      override = palette!(c.user, %{"key" => "override"})
      override = override |> Ecto.Changeset.change(source_palette_id: 999_999) |> Repo.update!()
      container = container!(c.user, override)
      exported = export!(c)
      assert exported["palettes"] == []
      assert [%{"palette" => uid}] = exported["containers"]
      assert uid == override.uid

      import!(exported, c.user)
      assert Repo.get!(Container, container.id).palette_id == override.id
      assert Repo.get!(Palette, override.id).source_palette_id == 999_999

      bundle =
        Map.put(exported, "palettes", [
          Snapshot.take!() |> elem(1) |> then(& &1.palettes[uid]) |> Brando.Content.Definition.Model.palette_record()
        ])

      assert {:error, message} = Definitions.plan(bundle, c.user)
      assert message =~ "shared-library overrides are unsupported"
    end

    test "a palette and a module never share a uid", c do
      fixtures!(c.path, ~w(paper))
      Factory.insert(:module, uid: "acme-palette-paper")
      assert {:error, message} = Definitions.plan(read!(c.path), c.user)
      assert message =~ ~s(palette "acme-palette-paper": the uid belongs to a module here)
    end

    test "a dry run compiles no container HEEx for a non-superuser, whatever grant a group holds", c do
      palette!(c.user) |> Ecto.Changeset.change(uid: "acme-palette-paper") |> Repo.update!()
      fixtures!(c.path, ~w(tinted))
      assert {:ok, bundle} = Definitions.read(c.path)

      bundle =
        Map.update!(bundle, "containers", fn [t] ->
          [Map.merge(t, %{"type" => "heex", "code" => "<section>{@content}</section>"})]
        end)

      editor = Factory.insert(:random_user, role: :admin)
      assert {:error, "authorization: forbidden"} = Definitions.plan(bundle, editor)

      put_test_env(:authorization_mode, :groups)
      alias Brando.Authorization.{Catalog, Grant, Groups, Migration, Scope}
      owner = Factory.insert(:random_user, role: :superuser)
      assert {:ok, _} = Migration.run()
      member = Factory.insert(:random_user, role: :user)
      scope = Scope.standalone(owner)
      assert {:ok, group} = Groups.create(scope, %{name: "Container authors"}, ["brando.admin.access"])

      for action <- [:create, :update],
          do: Repo.insert!(%Grant{group_id: group.id, permission_key: Catalog.get(action, Container).key})

      assert {:ok, :ok} = Groups.add_member(scope, group.id, member.id)
      assert {:error, "authorization: forbidden"} = Definitions.plan(bundle, member)
      assert Repo.aggregate(Container, :count) == 0
    end
  end

  describe "two environments seeded alike" do
    test "agree on the uids brando_245 derives, and an import adopts the other's rows without copies", c do
      put_test_env(:tenancy_mode, :multi)
      tables = ~w(content_modules content_table_templates content_refs content_vars content_blocks
                  content_definition_applies content_palettes content_containers activity_events)

      ids =
        for prefix <- ["tenant_seed_staging", "tenant_seed_production"], into: %{} do
          Brando.MigrationTemplates.create_environment(prefix, tables)

          [[palette]] =
            Brando.MigrationTemplates.rows(
              ~s|INSERT INTO "#{prefix}".content_palettes (name, namespace, key, status, colors, inserted_at, updated_at) | <>
                ~s|VALUES ('Paper', 'site', 'paper', 1, '[{"name": "Background", "key": "background", "hex_value": "#fff9f4"}]', now(), now()) RETURNING id|
            )

          [[container]] =
            Brando.MigrationTemplates.rows(
              ~s|INSERT INTO "#{prefix}".content_containers (name, namespace, code, type, palette_id, inserted_at, updated_at) | <>
                ~s|VALUES ('Tinted section', 'Sections', '{{ content }}', 'liquid', $1, now(), now()) RETURNING id|,
              [palette]
            )

          # A block of the environment's content points at both
          Brando.MigrationTemplates.query!(
            ~s|INSERT INTO "#{prefix}".content_blocks (uid, type, container_id, palette_id, inserted_at, updated_at) | <>
              ~s|VALUES ('seeded', 'container', $1, $2, now(), now())|,
            [container, palette]
          )

          {prefix, {palette, container}}
        end

      Brando.MigrationTemplates.up("brando_245_add_uids_to_palettes_and_containers.exs")

      exported =
        Tenant.with_prefix("tenant_seed_staging", fn ->
          assert {:ok, exported} = Definitions.export(Path.join(c.path, "staging"), c.user)
          assert [%{"uid" => "palette-site-paper"}] = exported.bundle["palettes"]

          assert [%{"uid" => "container-sections-tinted-section", "palette" => "palette-site-paper"}] =
                   exported.bundle["containers"]

          read!(exported.directory)
        end)

      Tenant.with_prefix("tenant_seed_production", fn ->
        assert {:ok, plan} = Definitions.plan(exported, c.user)
        assert Enum.map(plan.items, &{&1.action, &1.state}) == [{:noop, :in_sync}, {:noop, :in_sync}]
        assert {:ok, %{changes: []}} = Definitions.apply(plan, c.user)

        {palette, container} = ids["tenant_seed_production"]
        assert Repo.all(from(p in Palette, select: {p.id, p.uid})) == [{palette, "palette-site-paper"}]
        assert Repo.all(from(c in Container, select: {c.id, c.palette_id})) == [{container, palette}]

        assert Repo.all(from(b in Brando.Content.Block, select: {b.container_id, b.palette_id})) == [
                 {container, palette}
               ]

        # The import recorded them as applied here
        assert Repo.aggregate(Brando.Content.DefinitionApply, :count) == 2
      end)
    end
  end

  describe "after the commit" do
    test "the palette CSS and the entries that render the container are refreshed; refresh retries both", c do
      import!(read!(fixtures!(c.path, ~w(paper tinted))), c.user)
      page = page_with_tinted_section!(c.user)
      exported = export!(c)

      edited =
        exported
        |> Map.update!("palettes", fn [p] -> [put_in(p, ["colors", Access.at(0), "hex_value"], "#123456")] end)
        |> Map.update!("containers", fn [t] ->
          [Map.put(t, "code", ~s(<aside b-section="site-paper">{{ content }}</aside>))]
        end)

      assert {:ok, result} = Definitions.apply(elem(Definitions.plan(edited, c.user), 1), c.user)

      assert Enum.map(result.refresh, &{&1.uid, &1.status}) == [
               {"acme-palette-paper", :requested},
               {"acme-container-tinted", :requested}
             ]

      assert Brando.Pages.get_page!(page.id).rendered_blocks =~ ~s(<aside b-section="site-paper">)
      assert css() =~ "#123456"

      assert {:ok, refreshed} = Definitions.refresh(["acme-palette-paper", "acme-container-tinted"], c.user)
      assert Enum.all?(refreshed, &(&1.status == :requested))
      assert {:error, message} = Definitions.refresh(["nowhere"], c.user)
      assert message =~ "unknown definition"
    end

    test "a rolled-back import queues no render and leaves the palette CSS as it was", c do
      import!(read!(fixtures!(c.path, ~w(paper tinted))), c.user)
      page_with_tinted_section!(c.user)
      css = css()
      exported = export!(c)

      edited =
        exported
        |> Map.update!("palettes", fn [p] -> [put_in(p, ["colors", Access.at(0), "hex_value"], "#654321")] end)
        |> Map.update!("containers", fn [t] -> [Map.put(t, "help_text", "zz-fail")] end)

      Ecto.Adapters.SQL.query!(
        Repo.repo(),
        "ALTER TABLE content_containers ADD CONSTRAINT reject_styles_test CHECK (help_text IS DISTINCT FROM 'zz-fail')"
      )

      assert {:ok, plan} = Definitions.plan(edited, c.user)
      {result, run} = Definitions.track_refresh(fn -> Definitions.apply(plan, c.user) end)
      assert {:error, message} = result
      assert message =~ "no definitions were committed"
      assert Definitions.refresh_status(run) == %{rendered: 0, failed: [], pending: [], timed_out: false}
      assert hd(paper().colors).hex_value == "#fff9f4"
      assert css() == css
    end
  end

  describe "the guide's example" do
    test "a page with the tinted section and its paper palette prints the section and the nested module", c do
      fixtures!(c.path, ~w(paper tinted))

      File.write!(Path.join(c.path, "section_label.exs"), """
      defmodule MySite.Definitions.SectionLabel do
        use Brando.Content.Definition
        uid "acme-section-label"
        name en: "Section label"
        namespace en: "Sections"
        class "section-label"

        vars do
          var :label, :string do
            label "Label"
            default "Our work"
          end
        end

        template :liquid, "<p class=\\"section-label\\">{{ label }}</p>"
      end
      """)

      import!(read!(c.path), c.user)
      page = page_with_tinted_section!(c.user, Repo.get_by!(Module, uid: "acme-section-label"))

      assert Brando.Pages.get_page!(page.id).rendered_blocks =~
               ~r|<section b-section="site-paper">\s*<p class="section-label">Our work</p>\s*</section>|

      assert css() =~ ~s([b-section="site-paper"] {--background: #fff9f4;--foreground: #000000;})
    end
  end

  describe "files from before palettes and containers were definitions" do
    test "a bundle, lockfile and ZIP without them still load and plan", c do
      File.cp!("test/fixtures/definitions/hero.exs.txt", Path.join(c.path, "hero.exs"))
      assert {:ok, bundle} = Definitions.read(c.path)
      import!(bundle, c.user)
      assert {:ok, exported} = Definitions.export(Path.join(c.path, "out"), c.user, uids: ["hero-test"])

      # The lockfile as an earlier export wrote it
      lock_path = Path.join(exported.directory, "modules.lock.json")
      lock = lock_path |> File.read!() |> Jason.decode!()
      old = update_in(lock, ["baseline"], &Map.drop(&1, ~w(palettes containers)))
      File.write!(lock_path, Jason.encode!(old))
      assert {:ok, read} = Definitions.read(exported.directory)
      assert {:ok, plan} = Definitions.plan(read, c.user)
      assert Enum.map(plan.items, & &1.action) == [:noop]

      # A bundle kept from before, such as a stored plan's, has no lists for them
      stored = Map.drop(read, ~w(palettes containers))
      assert {:ok, %{items: [%{action: :noop}]}} = Definitions.plan(stored, c.user)

      files =
        exported.bundle |> Brando.Content.Definition.Writer.files() |> Map.put("modules.lock.json", Jason.encode!(old))

      assert {:ok, zip} = Brando.Content.Definition.Archive.pack(files)
      assert {:ok, %{bundle: %{"palettes" => [], "containers" => []}}} = Brando.Content.Definition.Archive.read(zip)
    end
  end

  # A page whose blocks hold a tinted section with the paper palette, and a
  # module inside it, rendered
  defp page_with_tinted_section!(user, module \\ nil) do
    module = module || Factory.insert(:module, code: "<p>inside</p>", vars: [], refs: [])

    blocks = [
      %{
        block: %{
          type: :container,
          uid: "tinted-#{System.unique_integer([:positive])}",
          source: "Elixir.Brando.Pages.Page.Blocks",
          container_id: tinted().id,
          palette_id: paper().id,
          children: [
            %{
              type: :module,
              module_id: module.id,
              source: "Elixir.Brando.Pages.Page.Blocks",
              uid: "label-#{System.unique_integer([:positive])}",
              vars: Enum.map(Repo.preload(module, :vars).vars, &Map.take(&1, [:key, :label, :type, :value])),
              refs: []
            }
          ]
        }
      }
    ]

    changeset =
      %Brando.Pages.Page{}
      |> Brando.Pages.Page.changeset(Factory.params_for(:page), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, blocks)
      |> Map.put(:action, :insert)

    {:ok, page} = Brando.Pages.create_page(changeset, user)
    {:ok, page} = Brando.Content.Blocks.render_entry(Brando.Pages.Page, page.id)
    page
  end

  defp tinted_uid, do: Repo.one!(from(c in Container, select: c.uid, limit: 1))

  defp write_module!(path, palette_uid) do
    File.write!(Path.join(path, "swatch.exs"), """
    defmodule Swatch do
      use Brando.Content.Definition
      uid "swatch"
      name en: "Swatch"
      namespace en: "Sections"
      class "swatch"

      vars do
        var :theme, :color do
          label "Theme"
          assets palette: #{inspect(palette_uid)}
        end
      end

      template :liquid, "<div>{{ theme }}</div>"
    end
    """)
  end
end

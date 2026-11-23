defmodule Brando.Content.DefinitionsPalettesContainersTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.{Container, Definitions, Module, Palette, TableTemplate}
  alias Brando.Content.Definition.{Baselines, Plan, Snapshot}
  alias Brando.Content.Definitions.Release
  alias Brando.Content.Definitions.Release.{Batches, Review}
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

    test "in groups mode, a module exporter's export leaves out the palettes and containers they may not export",
         c do
      palette = palette!(c.user)
      container!(c.user, palette)
      put_test_env(:authorization_mode, :groups)
      alias Brando.Authorization.{Catalog, Grant, Groups, Migration, Scope}
      owner = Factory.insert(:random_user, role: :superuser)
      assert {:ok, _} = Migration.run()
      member = Factory.insert(:random_user, role: :user)
      scope = Scope.standalone(owner)
      assert {:ok, group} = Groups.create(scope, %{name: "Module exporters"}, ["brando.admin.access"])
      Repo.insert!(%Grant{group_id: group.id, permission_key: Catalog.get(:export, Module).key})
      assert {:ok, :ok} = Groups.add_member(scope, group.id, member.id)

      module = Factory.insert(:module, uid: "plain")
      assert {:ok, exported} = Definitions.export(Path.join(c.path, "out"), member)
      assert Enum.map(exported.bundle["modules"], & &1["uid"]) == ["plain"]
      assert exported.bundle["palettes"] == [] and exported.bundle["containers"] == []
      assert Map.keys(exported.bundle["baseline"]["modules"]) == ["plain"]
      assert exported.bundle["baseline"]["palettes"] == %{}

      assert {:error, "authorization: forbidden"} =
               Definitions.export(Path.join(c.path, "container"), member, uids: [tinted_uid()])

      # A module whose var names the palette is refused by name
      Repo.delete!(module)
      write_module!(c.path, palette.uid)
      import!(read!(c.path), c.user)
      assert {:error, message} = Definitions.export(Path.join(c.path, "swatch"), member)
      assert message =~ ~s(module "swatch")
      assert message =~ ~s(palette "#{palette.uid}")
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

    test "a container whose palette is neither in the files nor here is refused, by name; one in the trash is a conflict",
         c do
      assert {:ok, bundle} = Definitions.read(fixtures!(c.path, ~w(tinted)))
      assert {:error, message} = Definitions.plan(bundle, c.user)
      assert message =~ ~s(container "acme-container-tinted")
      assert message =~ ~s(palette "acme-palette-paper" is neither in the files nor here)

      palette = palette!(c.user, %{"key" => "paper"})
      palette |> Ecto.Changeset.change(uid: "acme-palette-paper") |> Repo.update!()
      assert {:ok, plan} = Definitions.plan(bundle, c.user)
      assert actions(plan) == %{"acme-container-tinted" => :create}

      assert {:ok, _} = Brando.Content.delete_palette(palette.id, c.user)
      assert {:ok, plan} = Definitions.plan(bundle, c.user)
      assert [%{action: :conflict, reason: reason}] = plan.items
      assert reason =~ ~s(palette "acme-palette-paper" is in the trash here)
      refute Plan.applicable?(plan)
      assert {:error, message} = Definitions.plan(bundle, c.user, baseline: :lockfile)
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

    test "a selected module brings the palette only its table template's var names, in apply and export", c do
      palette = palette!(c.user)
      palette!(c.user, %{"key" => "other", "name" => "Other"})
      write_priced!(c.path, palette.uid)
      import!(read!(c.path), c.user)

      exported = export!(c, "selected", uids: ["priced"])
      assert Enum.map(exported["table_templates"], & &1["uid"]) == ["acme-prices"]
      assert Enum.map(exported["palettes"], & &1["uid"]) == [palette.uid]

      assert {:ok, %{selection: selection}} = Definitions.plan(export!(c), c.user, select: ["priced"])
      assert MapSet.equal?(selection, MapSet.new(["priced", "acme-prices", palette.uid]))
    end

    test "a container whose default palette is in the trash keeps the link through export and import", c do
      palette = palette!(c.user)
      container = container!(c.user, palette)
      assert {:ok, _} = Brando.Content.delete_palette(palette.id, c.user)

      assert {:ok, exported} = Definitions.export(Path.join(c.path, "out"), c.user)
      assert [%{"palette" => nil}] = exported.bundle["containers"]
      assert exported.unavailable == [%{uid: container.uid, container: "Tinted section", palette: "Paper"}]

      edited = Map.update!(read!(exported.directory), "containers", fn [t] -> [Map.put(t, "help_text", "Edited")] end)
      assert {:ok, plan} = Definitions.plan(edited, c.user)
      assert [%{action: :update, reason: reason}] = plan.items
      assert reason =~ ~s("Paper")
      assert {:ok, _} = Definitions.apply(plan, c.user)

      assert %{help_text: "Edited", palette_id: palette_id} = Repo.get!(Container, container.id)
      assert palette_id == palette.id
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

    test "a uid a definition in the trash has is not another kind's: the restore would make two", c do
      fixtures!(c.path, ~w(paper))
      module = Factory.insert(:module, uid: "acme-palette-paper")
      module |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

      assert {:error, message} = Definitions.plan(read!(c.path), c.user)
      assert message =~ ~s(palette "acme-palette-paper": the uid belongs to a module here)
    end

    test "refresh of a uid that a trashed definition of another kind also has is the active one's", c do
      import!(read!(fixtures!(c.path, ~w(paper))), c.user)
      # From before uids were checked against the trash
      module = Factory.insert(:module, uid: "acme-palette-paper")
      module |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

      assert {:ok, [%{status: :requested}]} = Definitions.refresh(["acme-palette-paper"], c.user)
    end

    # Planning a container or a module takes a superuser (their code), who
    # reads every palette; a table template is no code, and its var may name
    # a palette here the actor may not read
    test "a palette here the actor may not read is refused, by name", c do
      palette = palette!(c.user)
      put_test_env(:authorization_mode, :groups)
      alias Brando.Authorization.{Catalog, Grant, Groups, Migration, Scope}
      owner = Factory.insert(:random_user, role: :superuser)
      assert {:ok, _} = Migration.run()
      member = Factory.insert(:random_user, role: :user)
      scope = Scope.standalone(owner)
      assert {:ok, group} = Groups.create(scope, %{name: "Table authors"}, ["brando.admin.access"])

      for action <- [:create, :update],
          do: Repo.insert!(%Grant{group_id: group.id, permission_key: Catalog.get(action, TableTemplate).key})

      assert {:ok, :ok} = Groups.add_member(scope, group.id, member.id)
      write_priced!(c.path, palette.uid)
      File.rm!(Path.join(c.path, "priced.exs"))

      assert {:error, message} = Definitions.plan(read!(c.path), member)
      assert message =~ ~s(palette "#{palette.uid}": forbidden)

      Repo.insert!(%Grant{group_id: group.id, permission_key: Catalog.get(:read, Palette).key})
      assert {:ok, %{items: [%{action: :create}]}} = Definitions.plan(read!(c.path), member)
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

  describe "a release" do
    setup c do
      palette = palette!(c.user)
      container = container!(c.user, palette)
      release = Path.join(c.path, "release")
      assert {:ok, _} = Definitions.export(release, c.user, uids: [container.uid])
      File.rm!(Path.join(release, "modules.lock.json"))
      assert {:ok, %{adopted: 2}} = Release.plan(path: release, version: "1.0.0")
      %{palette: palette, container: container, release: release}
    end

    defp release_opts(c, extra), do: Keyword.merge([path: c.release, version: "2.0.0", user: c.user.id], extra)

    defp edit_release!(c, file, from, to) do
      path = Path.join(c.release, file)
      File.write!(path, String.replace(File.read!(path), from, to))
    end

    # The release adds a night palette and points the container at it, with
    # a new template, and changes the paper palette's background
    defp night_release!(c) do
      paper = File.read!(Path.join(c.release, "palettes/paper.exs"))

      File.write!(
        Path.join(c.release, "palettes/night.exs"),
        paper
        |> String.replace(c.palette.uid, "acme-palette-night")
        |> String.replace("Palettes.Paper", "Palettes.Night")
        |> String.replace(~s(key "paper"), ~s(key "night"))
        |> String.replace(~s(name "Paper"), ~s(name "Night"))
      )

      edit_release!(c, "containers/tinted-section.exs", ~s(palette "#{c.palette.uid}"), ~s(palette "acme-palette-night"))

      File.write!(
        Path.join(c.release, "containers/tinted-section.liquid"),
        ~s(<aside b-section="site-night">{{ content }}</aside>)
      )

      edit_release!(c, "palettes/paper.exs", "#fff9f4", "#f0f0f0")
    end

    test "plan and apply list palettes and containers; the container brings its new palette; revert restores", c do
      night_release!(c)
      assert {:ok, report} = Release.plan(release_opts(c, []))

      assert report.items |> Map.new(&{&1.uid, {&1.kind, &1.action}}) == %{
               "acme-palette-night" => {"palette", :create},
               c.palette.uid => {"palette", :update},
               c.container.uid => {"container", :update}
             }

      text = Enum.join(Release.lines(report), "\n")
      assert text =~ "create palette Night (acme-palette-night): new"
      assert text =~ "update container Tinted section (#{c.container.uid})"

      manual(fn ->
        assert {:ok, %{batch_id: batch_id, result: result}} =
                 Release.apply([c.container.uid], release_opts(c, wait: false))

        assert result.changes |> Enum.map(& &1.uid) |> Enum.sort() == Enum.sort(["acme-palette-night", c.container.uid])
        night = Repo.get_by!(Palette, uid: "acme-palette-night")
        container = Repo.get!(Container, c.container.id)
        assert container.palette_id == night.id
        assert container.code =~ "<aside"
        # Not selected: the paper palette stays as it was
        assert hd(Repo.get!(Palette, c.palette.id).colors).hex_value == "#fff9f4"

        assert {:ok, %{reverted: [%{uid: uid}], created: ["acme-palette-night"]}} =
                 Batches.revert(Batches.get(batch_id), c.user)

        assert uid == c.container.uid
        container = Repo.get!(Container, c.container.id)
        assert container.palette_id == c.palette.id
        assert container.code == c.container.code

        assert {:ok, %{batch_id: batch_id}} = Release.apply([c.palette.uid], release_opts(c, wait: false))
        assert hd(Repo.get!(Palette, c.palette.id).colors).hex_value == "#f0f0f0"
        assert {:ok, %{reverted: [_]}} = Batches.revert(Batches.get(batch_id), c.user)
        assert swatches(Repo.get!(Palette, c.palette.id)) == swatches(c.palette)
      end)
    end

    test "a revert lists a container whose previous palette is now in the trash as a conflict", c do
      night_release!(c)

      manual(fn ->
        assert {:ok, %{batch_id: batch_id}} = Release.apply([c.container.uid], release_opts(c, wait: false))
        assert {:ok, _} = Brando.Content.delete_palette(c.palette.id, c.user)

        assert {:ok, %{revert: [], conflicts: [conflict]}} = Batches.preview(Batches.get(batch_id), c.user)
        assert %{uid: uid, action: :conflict, reason: reason} = conflict
        assert uid == c.container.uid
        assert reason =~ ~s(palette "#{c.palette.uid}" is in the trash here)
      end)
    end

    test "a container whose palette is in conflict is refused, by name", c do
      edit_release!(c, "palettes/paper.exs", "#fff9f4", "#f0f0f0")
      File.write!(Path.join(c.release, "containers/tinted-section.liquid"), "<div>{{ content }}</div>")
      assert {:ok, _} = Brando.Content.update_palette(c.palette.id, %{name: "Edited here"}, c.user)

      assert {:error, message} = Release.apply([c.container.uid], release_opts(c, []))
      assert message =~ "(#{c.palette.uid}): target changed"
      assert Repo.get!(Container, c.container.id).code == c.container.code
    end

    test "the review lists a container with its palette in one row, and a palette's colours", c do
      night_release!(c)
      assert {:ok, report} = Release.plan(release_opts(c, []))
      rows = Review.rows(report)

      assert [%{uid: container_uid, kind: "container", uids: uids}, %{uid: palette_uid, kind: "palette"}] =
               Enum.sort_by(rows, &(&1.kind != "container"))

      assert container_uid == c.container.uid and palette_uid == c.palette.uid
      assert Enum.sort(uids) == Enum.sort([c.container.uid, "acme-palette-night"])

      %{here: here, release: release} = Review.definitions(report, c.palette.uid)

      assert [%{key: "background", change: :changed}, %{key: "foreground", change: :same}] =
               Review.structure(here, release).colors
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

  describe "a release batch from before palettes and containers were definitions" do
    # A release changed the module whose var names the palette, and its
    # rows are as an apply wrote them then: the palette named by a token
    # mapped to its id, in the definitions and their digests
    setup c do
      palette = palette!(c.user)
      write_module!(c.path, palette.uid)
      import!(read!(c.path), c.user)
      release = Path.join(c.path, "release")
      assert {:ok, _} = Definitions.export(release, c.user, uids: ["swatch"])
      File.rm!(Path.join(release, "modules.lock.json"))
      assert {:ok, %{adopted: 1}} = Release.plan(path: release, version: "1.0.0")
      [template] = for path <- Path.wildcard(Path.join(release, "**/swatch*")), File.read!(path) =~ "<div>", do: path
      File.write!(template, String.replace(File.read!(template), "<div>", "<p>"))

      batch_id =
        manual(fn ->
          assert {:ok, %{batch_id: batch_id}} = Release.apply(["swatch"], release_opts(release, c, "2.0.0"))
          batch_id
        end)

      token = "palette:#{palette.id}"
      old = &put_in(&1, ["vars", Access.at(0), "assets", "palette"], token)

      for row <- Repo.all(from(a in Brando.Content.DefinitionApply, where: a.uid == "swatch")) do
        {definition, previous} = {old.(row.definition), row.previous && old.(row.previous)}

        row
        |> Ecto.Changeset.change(
          definition: definition,
          digest: Baselines.digest(definition, %{}),
          previous: previous,
          previous_digest: previous && Baselines.digest(previous, %{}),
          references: %{token => %{"kind" => "palette", "id" => palette.id}}
        )
        |> Repo.update!()
      end

      %{palette: palette, release: release, template: template, batch_id: batch_id}
    end

    defp release_opts(release, c, version), do: [path: release, version: version, user: c.user.id, wait: false]

    test "still loads and reverts", c do
      manual(fn ->
        assert {:ok, %{revert: [%{uid: "swatch"}], conflicts: []}} = Batches.preview(Batches.get(c.batch_id), c.user)
        assert {:ok, %{reverted: [%{uid: "swatch"}]}} = Batches.revert(Batches.get(c.batch_id), c.user)
      end)

      module = Repo.get_by!(Module, uid: "swatch") |> Repo.preload(:vars)
      assert module.code == "<div>{{ theme }}</div>"
      assert [%{palette_id: palette_id}] = module.vars
      assert palette_id == c.palette.id
    end

    test "the next release updates the module it applied, as no edit here", c do
      File.write!(c.template, String.replace(File.read!(c.template), "<p>", "<p class=\"next\">"))
      assert {:ok, report} = Release.plan(release_opts(c.release, c, "3.0.0"))
      assert [%{uid: "swatch", action: :update}] = Enum.filter(report.items, &(&1.uid == "swatch"))
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

  defp manual(fun), do: Oban.Testing.with_testing_mode(:manual, fun)

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

  defp write_priced!(path, palette_uid) do
    File.write!(Path.join(path, "prices.exs"), """
    defmodule Prices do
      use Brando.Content.Definition
      kind :table_template
      uid "acme-prices"
      name "Prices"

      vars do
        var :tone, :color do
          label "Tone"
          assets palette: #{inspect(palette_uid)}
        end
      end
    end
    """)

    File.write!(Path.join(path, "priced.exs"), """
    defmodule Priced do
      use Brando.Content.Definition
      uid "priced"
      name en: "Priced"
      namespace en: "Sections"
      class "priced"
      table_template Prices
      template :liquid, "<div></div>"
    end
    """)
  end
end

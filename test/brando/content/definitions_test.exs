defmodule Brando.Content.DefinitionsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.{Block, Definitions, Module, Ref, TableTemplate, Var}
  alias Brando.Content.Definition.{Model, Snapshot}
  alias Brando.{Factory, Repo, Tenant}
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    path = Path.join(System.tmp_dir!(), "brando-import-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    File.cp!("test/fixtures/definitions/hero.exs.txt", Path.join(path, "hero.exs"))
    {:ok, bundle} = Definitions.read(path)
    on_exit(fn -> File.rm_rf!(path) end)
    %{user: user, path: path, bundle: bundle}
  end

  defp apply_bundle!(bundle, user) do
    assert {:ok, plan} = Definitions.plan(bundle, user)
    assert {:ok, result} = Definitions.apply(plan, user)
    result
  end

  defp snapshot do
    {bundle, _} = Snapshot.take!()
    bundle
  end

  defp hero, do: Repo.get_by!(Module, uid: "hero-test") |> Repo.preload([:refs, :vars])

  defp edit(bundle, fun), do: Map.update!(bundle, "modules", fn [module] -> [fun.(module)] end)

  test "planning is read-only; create, export, import is an identity-preserving no-op", c do
    assert {:ok, plan} = Definitions.plan(c.bundle, c.user)
    assert [%{action: :create}] = plan.items
    assert Repo.aggregate(Module, :count) == 0
    assert {:ok, %{changes: [%{action: :create}]}} = Definitions.apply(plan, c.user)
    before = hero()
    assert before.version == 1

    assert {:ok, exported} = Definitions.export(Path.join(c.path, "out"), c.user)
    assert {:ok, bundle} = Definitions.read(exported.directory)
    assert bundle == exported.bundle
    assert {:ok, plan} = Definitions.plan(bundle, c.user)
    assert [%{action: :noop}] = plan.items
    assert {:ok, %{changes: [], refresh: []}} = Definitions.apply(plan, c.user)
    assert hero() == before
    assert Repo.aggregate(Module, :count) == 1
    assert Repo.aggregate(Ref, :count) == 1
    assert Repo.aggregate(Var, :count) == 1
  end

  test "updates settings and defaults once while preserving identities and editor content", c do
    apply_bundle!(c.bundle, c.user)
    before = hero()
    [ref] = before.refs
    [var] = before.vars

    block =
      %Block{}
      |> Changeset.change(%{
        uid: "editor-block",
        type: :module,
        module_id: before.id,
        module_version: before.version,
        creator_id: c.user.id,
        source: Brando.Pages.Page.Blocks,
        sequence: 0
      })
      |> Repo.insert!()

    editor_ref =
      %Ref{}
      |> Ref.changeset(
        %{
          "uid" => "editor-ref",
          "name" => ref.name,
          "block_id" => block.id,
          "data" => %{"type" => "header", "data" => %{"level" => 1, "text" => "Editor headline"}}
        },
        c.user
      )
      |> Repo.insert!()

    editor_var =
      %Var{}
      |> Var.changeset(
        %{"key" => var.key, "type" => "select", "label" => "Theme", "value" => "dark", "block_id" => block.id},
        c.user
      )
      |> Repo.insert!()

    bundle =
      snapshot()
      |> edit(fn definition ->
        definition
        |> put_in(["refs", Access.at(0), "data", "data", "level"], 2)
        |> put_in(["refs", Access.at(0), "data", "data", "text"], "New default")
        |> put_in(["vars", Access.at(0), "width"], "full")
        |> put_in(["vars", Access.at(0), "options"], [%{"label" => "Dark mode", "value" => "dark"}])
      end)

    assert {:ok, plan} = Definitions.plan(bundle, c.user)
    assert [%{action: :update, block_count: 1}] = plan.items
    assert {:ok, %{refresh: [%{status: :requested}]}} = Definitions.apply(plan, c.user)
    after_import = hero()
    assert after_import.id == before.id
    assert after_import.version == before.version + 1
    assert hd(after_import.refs).id == ref.id
    assert hd(after_import.refs).uid == ref.uid
    assert hd(after_import.vars).id == var.id
    assert hd(after_import.vars).width == :full
    assert Repo.get!(Ref, editor_ref.id).data.data.text == "Editor headline"
    assert Repo.get!(Ref, editor_ref.id).data.data.level == 2
    assert Repo.get!(Var, editor_var.id).value == "dark"
    assert Repo.get!(Block, block.id).module_version == after_import.version
    assert %{changes: []} = apply_bundle!(bundle, c.user)
    assert hero() == after_import
  end

  test "baseline conflicts and changes after planning never overwrite the target", c do
    apply_bundle!(c.bundle, c.user)
    exported = snapshot()
    desired = edit(exported, &Map.put(&1, "code", "<p>Desired</p>"))
    assert {:ok, plan} = Definitions.plan(desired, c.user)
    assert [%{action: :update}] = plan.items
    hero() |> Module.changeset(%{code: "<p>Admin edit</p>"}, c.user) |> Repo.update!()
    assert {:error, message} = Definitions.apply(plan, c.user)
    assert message =~ "target changed"
    assert hero().code == "<p>Admin edit</p>"
    assert {:ok, conflicting} = Definitions.plan(desired, c.user)
    assert [%{action: :conflict, reason: "target changed since export"}] = conflicting.items
    assert {:error, _} = Definitions.apply(conflicting, c.user)
  end

  test "destructive changes block the entire bundle", c do
    apply_bundle!(c.bundle, c.user)
    before = hero()
    bundle = snapshot() |> edit(&Map.put(&1, "vars", []))
    [definition] = c.bundle["modules"]
    new = definition |> Map.put("uid", "new-hero") |> Map.put("refs", [])
    bundle = Map.update!(bundle, "modules", &(&1 ++ [new]))
    assert {:ok, plan} = Definitions.plan(bundle, c.user)
    assert Enum.any?(plan.items, &(&1.action == :migration_required))
    assert {:error, _} = Definitions.apply(plan, c.user)
    assert Repo.aggregate(Module, :count) == 1
    assert hero() == before
  end

  test "children and table dependencies round-trip and selecting a child includes its tree", c do
    [child] = c.bundle["modules"]
    table = %{"kind" => "table_template", "uid" => "table-uid", "name" => "Rows", "vars" => child["vars"]}
    child = Map.put(child, "table_template", table["uid"])

    parent =
      child
      |> Map.merge(%{
        "uid" => "parent",
        "multi" => true,
        "children" => [child["uid"]],
        "refs" => [],
        "vars" => [],
        "table_template" => nil
      })

    bundle = %{c.bundle | "modules" => [parent, child], "table_templates" => [table]} |> Model.canonicalize()
    apply_bundle!(bundle, c.user)
    assert hero().parent_id == Repo.get_by!(Module, uid: "parent").id
    assert hero().table_template_id == Repo.get_by!(TableTemplate, uid: "table-uid").id
    assert {:ok, exported} = Definitions.export(Path.join(c.path, "tree"), c.user, uids: ["hero-test"])
    assert length(exported.bundle["modules"]) == 2
    assert {:ok, imported} = Definitions.read(exported.directory)
    assert imported == exported.bundle
    assert %{changes: []} = apply_bundle!(imported, c.user)
    assert Repo.aggregate(TableTemplate, :count) == 1
  end

  test "new installations require explicit external asset mappings", c do
    image = Factory.insert(:image)
    destination = Factory.insert(:image)
    [definition] = c.bundle["modules"]
    definition = put_in(definition, ["refs", Access.at(0), "assets", "image"], "cover")

    bundle =
      %{c.bundle | "modules" => [definition]}
      |> Map.merge(%{
        "source" => "another-installation",
        "baseline" => %{"modules" => %{"hero-test" => "source-digest"}},
        "references" => %{"cover" => %{"kind" => "image", "id" => image.id}}
      })

    assert {:error, message} = Definitions.plan(bundle, c.user)
    assert message =~ "requires a destination reference mapping"
    assert {:ok, plan} = Definitions.plan(bundle, c.user, references: %{"cover" => destination.id})
    assert [%{action: :create}] = plan.items
    assert {:ok, _} = Definitions.apply(plan, c.user)
    assert hd(hero().refs).image_id == destination.id
    assert {:ok, exported} = Definitions.export(Path.join(c.path, "assets"), c.user)
    assert {:ok, read} = Definitions.read(exported.directory)
    assert read == exported.bundle
    assert %{changes: []} = apply_bundle!(read, c.user)
  end

  test "invalid templates and reserved variables fail before writing", c do
    assert {:error, _} = Definitions.plan(edit(c.bundle, &Map.put(&1, "code", "<div>")), c.user)
    bad = edit(c.bundle, &put_in(&1, ["vars", Access.at(0), "key"], "block"))
    assert {:error, message} = Definitions.plan(bad, c.user)
    assert message =~ "reserved"
    assert Repo.aggregate(Module, :count) == 0
  end

  test "Markdown sources require destination mappings and preserve pins on round-trip", c do
    %{bundle: bundle, source: source, version: version, mappings: mappings} = markdown_fixture(c)
    assert {:error, message} = Definitions.plan(bundle, c.user)
    assert message =~ "requires a destination reference mapping"
    assert {:ok, plan} = Definitions.plan(bundle, c.user, references: mappings)
    assert {:ok, _} = Definitions.apply(plan, c.user)
    before = hero()
    [ref] = before.refs
    assert ref.data.data.source_id == source.id
    assert ref.data.data.version_id == version.id
    assert ref.data.data.policy == :pinned
    assert {:ok, exported} = Definitions.export(Path.join(c.path, "markdown"), c.user)
    assert {:ok, read} = Definitions.read(exported.directory)
    assert read == exported.bundle
    assert %{changes: []} = apply_bundle!(read, c.user)
    assert hero() == before

    other =
      Repo.insert!(%Brando.MarkdownSources.Source{
        name: "Other",
        connection: "docs",
        ref: "refs/heads/main",
        path: "other.md"
      })

    assert {:error, message} = Definitions.plan(bundle, c.user, references: %{mappings | "document" => other.id})
    assert message =~ "Choose an available source and an exact version"
    assert hero() == before
  end

  test "module import cannot bypass Markdown publication permissions", c do
    %{bundle: bundle, mappings: mappings} = markdown_fixture(c)
    put_test_env(:authorization_mode, :groups)
    alias Brando.Authorization.{Catalog, Groups, Migration, Scope}
    owner = Factory.insert(:random_user, role: :superuser)
    assert {:ok, _} = Migration.run()
    editor = Factory.insert(:random_user, role: :user)
    scope = Scope.standalone(owner)
    grants = [Catalog.get(:create, Module).key, "brando.admin.access", "brando.markdown_sources.read"]
    assert {:ok, group} = Groups.create(scope, %{name: "Module authors"}, grants)
    assert {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)
    assert {:error, message} = Definitions.plan(bundle, editor, references: mappings)
    assert message =~ "You cannot publish Markdown source updates"
    assert Repo.aggregate(Module, :count) == 0
  end

  defp markdown_fixture(c) do
    put_test_env(:markdown_sources,
      connections: %{
        "docs" => %{repository: "acme/docs", repository_id: 42, secret: String.duplicate("s", 40), destinations: [nil]}
      }
    )

    source =
      Repo.insert!(%Brando.MarkdownSources.Source{
        name: "Docs",
        connection: "docs",
        ref: "refs/heads/main",
        path: "start.md"
      })

    version =
      Repo.insert!(%Brando.MarkdownSources.Version{
        source_id: source.id,
        commit: String.duplicate("a", 40),
        markdown: "first",
        html: "<p>first</p>",
        content_hash: "first",
        repository: "acme/docs",
        path: source.path
      })

    bundle =
      edit(c.bundle, fn definition ->
        put_in(definition, ["refs", Access.at(0), "data"], %{
          "type" => "markdown_source",
          "data" => %{"source_id" => "document", "version_id" => "revision", "policy" => "pinned"}
        })
      end)

    %{
      bundle: Map.put(bundle, "source", "another-installation"),
      source: source,
      version: version,
      mappings: %{"document" => source.id, "revision" => version.id}
    }
  end

  test "missing baselines, deleted definitions, wrong scopes and shared overrides are rejected", c do
    apply_bundle!(c.bundle, c.user)
    before = snapshot()
    assert {:ok, plan} = Definitions.plan(edit(c.bundle, &Map.put(&1, "class", "changed")), c.user)
    assert [%{action: :conflict}] = plan.items
    assert {:ok, plan} = Definitions.plan(before, c.user)
    put_test_env(:tenancy_mode, :multi)

    Tenant.with_prefix("tenant_other_staging", fn ->
      assert {:error, message} = Definitions.apply(plan, c.user)
      assert message =~ "another installation or environment"
    end)

    put_test_env(:tenancy_mode, :none)
    hero() |> Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)) |> Repo.update!()
    assert {:error, message} = Definitions.plan(before, c.user)
    assert message =~ "deleted or unavailable"
  end

  test "export never overwrites authored files", c do
    apply_bundle!(c.bundle, c.user)
    assert {:error, message} = Definitions.export(c.path, c.user)
    assert message =~ "new directory"
    assert File.read!(Path.join(c.path, "hero.exs")) == File.read!("test/fixtures/definitions/hero.exs.txt")
  end

  test "the CLI dry run preserves files and imports advance the baseline for the next edit", c do
    import_args = ["import", "--from", c.path, "--user", to_string(c.user.id)]
    source = File.read!(Path.join(c.path, "hero.exs"))
    ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Brando.Modules.run(import_args ++ ["--dry-run"]) end)
    assert Repo.aggregate(Module, :count) == 0
    refute File.exists?(Path.join(c.path, "modules.lock.json"))
    ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Brando.Modules.run(import_args) end)
    assert File.read!(Path.join(c.path, "hero.exs")) == source
    File.write!(Path.join(c.path, "hero.exs"), String.replace(source, "class \"hero\"", "class \"new-class\""))
    ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Brando.Modules.run(import_args) end)
    assert hero().class == "new-class"
    version = hero().version
    ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Brando.Modules.run(import_args) end)
    assert hero().version == version
    assert {:ok, [%{status: :requested}]} = Definitions.refresh(["hero-test"], c.user)
  end

  test "tenant imports only update the selected environment and public library access is refused", c do
    apply_bundle!(c.bundle, c.user)
    original = hero()
    put_test_env(:tenancy_mode, :multi)

    for prefix <- ["tenant_dsl_staging", "tenant_dsl_production"] do
      Ecto.Adapters.SQL.query!(Repo.repo(), ~s(CREATE SCHEMA "#{prefix}"))

      for table <- ~w(content_modules content_table_templates content_refs content_vars content_blocks) do
        Ecto.Adapters.SQL.query!(
          Repo.repo(),
          ~s|CREATE TABLE "#{prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|
        )
      end
    end

    assert {:error, message} = Definitions.plan(c.bundle, c.user)
    assert message =~ "select a site/environment"

    Tenant.with_prefix("tenant_dsl_staging", fn ->
      apply_bundle!(c.bundle, c.user)
      bundle = snapshot() |> edit(&Map.put(&1, "class", "staging"))
      apply_bundle!(bundle, c.user)
      assert hero().class == "staging"
    end)

    Tenant.with_prefix("tenant_dsl_production", fn -> assert Repo.aggregate(Module, :count) == 0 end)
    assert Repo.get!(Module, original.id, prefix: "public").class == "hero"
    assert Tenant.current_prefix() == nil
  end

  test "authorization is checked again at apply and denied exports write no files", c do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()
    denied = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    assert {:error, "authorization: forbidden"} = Definitions.plan(c.bundle, denied)
    assert {:ok, plan} = Definitions.plan(c.bundle, c.user)
    assert {:error, "authorization: forbidden"} = Definitions.apply(plan, denied)
    assert {:ok, _} = Definitions.apply(plan, c.user)
    output = Path.join(c.path, "forbidden")
    assert {:error, _} = Definitions.export(output, denied)
    refute File.exists?(output)
    assert {:ok, _} = Definitions.export(Path.join(c.path, "permitted"), c.user)
  end

  test "a late database failure rolls back earlier definitions in the same import", c do
    [first] = c.bundle["modules"]
    second = first |> Map.put("uid", "zz-fail") |> Map.put("refs", [])
    bundle = Map.put(c.bundle, "modules", [first, second])

    Ecto.Adapters.SQL.query!(
      Repo.repo(),
      "ALTER TABLE content_modules ADD CONSTRAINT reject_dsl_test CHECK (uid <> 'zz-fail')"
    )

    assert {:ok, plan} = Definitions.plan(bundle, c.user)
    assert {:error, message} = Definitions.apply(plan, c.user)
    assert message =~ "no definitions were committed"
    assert Repo.aggregate(Module, :count) == 0
    assert Repo.aggregate(Ref, :count) == 0
    assert Repo.aggregate(Var, :count) == 0
  end

  test "a shared override and a borrowed ref UID cannot be imported as local definitions", c do
    apply_bundle!(c.bundle, c.user)
    local = hero()
    bundle = snapshot()
    local |> Changeset.change(source_module_id: 123) |> Repo.update!()
    assert {:error, message} = Definitions.plan(bundle, c.user)
    assert message =~ "shared-library overrides"
    assert {:error, _} = Definitions.export(Path.join(c.path, "shared"), c.user, uids: [local.uid])

    child =
      local
      |> Map.from_struct()
      |> Map.take(Model.module_fields())
      |> Map.merge(%{uid: "shared-child", parent_id: local.id})

    child = %Module{} |> Module.changeset(child, c.user) |> Repo.insert!()
    assert {:ok, exported} = Definitions.export(Path.join(c.path, "local-only"), c.user)
    assert exported.bundle["modules"] == []
    assert {:ok, empty} = Definitions.read(exported.directory)
    assert empty == exported.bundle
    assert %{changes: []} = apply_bundle!(empty, c.user)
    child_bundle = edit(c.bundle, &Map.merge(&1, %{"uid" => child.uid, "refs" => []}))
    assert {:error, message} = Definitions.plan(child_bundle, c.user)
    assert message =~ "shared-library descendants"
    Repo.delete!(child)
    Repo.update!(Changeset.change(local, source_module_id: nil))
    borrowed = edit(c.bundle, &Map.put(&1, "uid", "new-lineage"))
    assert {:error, message} = Definitions.plan(borrowed, c.user)
    assert message =~ "ref UID belongs"
  end

  test "new asset tokens can replace and clear defaults without losing baseline bindings", c do
    first = Factory.insert(:image)
    second = Factory.insert(:image)
    bundle = edit(c.bundle, &put_in(&1, ["refs", Access.at(0), "assets", "image"], "cover"))
    assert {:ok, plan} = Definitions.plan(bundle, c.user, references: %{"cover" => first.id})
    assert {:ok, applied} = Definitions.apply(plan, c.user)
    assert {:error, message} = Definitions.plan(applied.bundle, c.user, references: %{"cover" => second.id})
    assert message =~ "new token"
    replaced = edit(applied.bundle, &put_in(&1, ["refs", Access.at(0), "assets", "image"], "replacement"))
    assert {:ok, plan} = Definitions.plan(replaced, c.user, references: %{"replacement" => second.id})
    assert [%{action: :update}] = plan.items
    assert {:ok, applied} = Definitions.apply(plan, c.user)
    assert hd(hero().refs).image_id == second.id
    cleared = edit(applied.bundle, &put_in(&1, ["refs", Access.at(0), "assets", "image"], nil))
    apply_bundle!(cleared, c.user)
    assert hd(hero().refs).image_id == nil
  end

  test "attaching a newly created table to an existing module requires a migration", c do
    apply_bundle!(c.bundle, c.user)
    bundle = snapshot() |> edit(&Map.put(&1, "table_template", "new-table"))
    table = %{"kind" => "table_template", "uid" => "new-table", "name" => "Rows", "vars" => []}
    bundle = Map.put(bundle, "table_templates", [table])
    assert {:ok, plan} = Definitions.plan(bundle, c.user)
    assert Enum.any?(plan.items, &(&1.uid == "hero-test" and &1.action == :migration_required))
    assert {:error, _} = Definitions.apply(plan, c.user)
    assert Repo.aggregate(TableTemplate, :count) == 0
    assert hero().table_template_id == nil
  end
end

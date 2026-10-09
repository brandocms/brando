defmodule Brando.Content.ModuleWriteWithAITest do
  @moduledoc """
  A module's Write with AI setting (`write_with_ai`) is off unless turned on,
  and goes wherever the module goes: duplication, the module export and
  import, the module definition files and a version bump for the shared
  library's copies.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content
  alias Brando.Content.{Definitions, Module, ModuleDiff}
  alias Brando.{Factory, Repo}

  defp create_module(user, attrs) do
    {:ok, module} =
      %{
        name: %{"en" => "Text"},
        namespace: %{"en" => "general"},
        help_text: %{"en" => "Text"},
        class: "text-#{System.unique_integer([:positive])}",
        code: "{% ref refs.body %}",
        refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Text"}}}]
      }
      |> Map.merge(attrs)
      |> Content.create_module(user)

    module
  end

  setup do
    %{user: Factory.insert(:random_user)}
  end

  test "is off in a new module", %{user: user} do
    refute create_module(user, %{}).write_with_ai
  end

  test "is turned on in the module editor's form, and a change bumps the version", %{user: user} do
    module = create_module(user, %{})

    {:ok, updated} = module |> Module.changeset(%{"write_with_ai" => "true"}, user) |> Repo.update()

    assert updated.write_with_ai
    assert updated.version == module.version + 1
    assert ModuleDiff.classify(ModuleDiff.diff(module, updated)) == :metadata
  end

  test "a duplicate keeps it, as a new module", %{user: user} do
    module = create_module(user, %{write_with_ai: true})

    {:ok, copy} = Content.duplicate_module(module.id, user)

    assert copy.id != module.id
    assert copy.uid != module.uid
    assert copy.version == 1
    assert copy.write_with_ai
  end

  test "the module export carries it, and an export from before it imports as off", %{user: user} do
    module = create_module(user, %{write_with_ai: true})

    [decoded] = export(module, user)
    {:ok, imported} = Content.import_module_with_children(decoded)
    assert imported.id != module.id
    assert Repo.get!(Module, imported.id).write_with_ai

    [older] = export(module, user)
    {:ok, older} = older |> Map.delete(:write_with_ai) |> Content.import_module_with_children()
    refute Repo.get!(Module, older.id).write_with_ai
  end

  # Exported as the module list's "Export modules" does, and read back
  defp export(module, user) do
    %{filter: %{ids: [module.id]}, preload: [:vars, :refs, children: [:vars, :refs]]}
    |> Content.list_modules!()
    |> Content.prepare_modules_for_export(user.id)
    |> Content.serialize_modules()
    |> Content.deserialize_modules()
  end

  test "the module definition files carry it", %{user: user} do
    create_module(user, %{uid: "write-with-ai-test", write_with_ai: true})
    directory = Path.join(System.tmp_dir!(), "brando-write-with-ai-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(directory) end)

    assert {:ok, exported} = Definitions.export(directory, user, uids: ["write-with-ai-test"])
    [file] = Enum.filter(exported.files, &String.ends_with?(&1, ".exs"))
    assert File.read!(Path.join(directory, file)) =~ "\n  write_with_ai true\n"

    assert {:ok, bundle} = Definitions.read(directory)
    assert [%{"write_with_ai" => true}] = bundle["modules"]
    assert {:ok, %{items: [%{action: :noop}]}} = Definitions.plan(bundle, user)

    # Turned off in the file, it is turned off in the module
    off = put_in(bundle, ["modules", Access.at(0), "write_with_ai"], false)
    assert {:ok, %{items: [%{action: :update}]} = plan} = Definitions.plan(off, user)
    assert {:ok, _} = Definitions.apply(plan, user)
    refute Repo.get_by!(Module, uid: "write-with-ai-test").write_with_ai
  end
end

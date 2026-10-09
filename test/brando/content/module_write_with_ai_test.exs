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

  import Ecto.Query, only: [from: 2]

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

  test "a duplicated multi module takes copies of its children, refs and vars, and joins its module sets",
       %{user: user} do
    parent =
      create_module(user, %{
        class: "cards",
        multi: true,
        vars: [%{type: :text, label: "Heading", key: "heading", value: "Cards", sequence: 0}]
      })

    child = create_module(user, %{class: "card", parent_id: parent.id, sequence: 0})
    other = create_module(user, %{class: "other"})

    {:ok, set} = Content.create_module_set(%{title: "Sections"}, user)

    for {module, sequence} <- [{other, 0}, {parent, 1}],
        do: Repo.insert!(%Brando.Content.ModuleSetModule{module_set_id: set.id, module_id: module.id, sequence: sequence})

    {:ok, copy} = Content.duplicate_module(parent.id, user)
    copy = Repo.preload(Repo.get!(Module, copy.id), [:vars, :refs, children: [:vars, :refs]])

    assert copy.class == "cards-copy"
    assert [%{key: "heading", value: "Cards"}] = copy.vars
    assert [%{name: "body"} = ref] = copy.refs
    refute ref.uid == hd(Repo.preload(parent, :refs).refs).uid

    assert [copied_child] = copy.children
    assert copied_child.id != child.id
    assert copied_child.uid != child.uid
    assert copied_child.class == "card"
    assert [%{name: "body"}] = copied_child.refs

    # The original keeps its own child, refs and vars
    original = Repo.preload(Repo.get!(Module, parent.id), [:vars, :refs, :children])
    assert [%{id: child_id}] = original.children
    assert child_id == child.id
    assert [_] = original.refs
    assert [_] = original.vars

    members =
      Repo.all(
        from msm in Brando.Content.ModuleSetModule,
          where: msm.module_set_id == ^set.id,
          order_by: [asc: msm.sequence, asc: msm.id],
          select: msm.module_id
      )

    assert members == [other.id, parent.id, copy.id]

    # A second copy takes the next free class
    {:ok, again} = Content.duplicate_module(parent.id, user)
    assert again.class == "cards-copy-2"
  end

  test "a duplicated multi module copies three children, each with its own refs and vars", %{user: user} do
    image = Factory.insert(:image)
    parent = create_module(user, %{class: "slides", multi: true})

    children =
      for n <- 1..3 do
        refs =
          [
            %{
              name: "body",
              uid: Brando.Utils.generate_uid(),
              sequence: 0,
              data: %{type: "text", data: %{text: "Text #{n}"}}
            },
            %{
              name: "lede",
              uid: Brando.Utils.generate_uid(),
              sequence: 1,
              data: %{type: "text", data: %{text: "Lede #{n}"}}
            }
          ] ++
            if n == 2,
              do: [
                %{
                  name: "photo",
                  uid: Brando.Utils.generate_uid(),
                  sequence: 2,
                  image_id: image.id,
                  data: %{type: "picture", data: %{}}
                }
              ],
              else: []

        create_module(user, %{
          class: "slide-#{n}",
          parent_id: parent.id,
          sequence: n,
          refs: refs,
          vars: [
            %{type: :text, label: "Title", key: "title", value: "Title #{n}", sequence: 0},
            %{type: :text, label: "Kicker", key: "kicker", value: "Kicker #{n}", sequence: 1}
          ]
        })
      end

    {:ok, copy} = Content.duplicate_module(parent.id, user)

    copied =
      Module
      |> Repo.get!(copy.id)
      |> Repo.preload(
        children: [
          vars: Ecto.Query.from(v in Brando.Content.Var, order_by: v.sequence),
          refs: Ecto.Query.from(r in Brando.Content.Ref, order_by: r.sequence)
        ]
      )
      |> Map.fetch!(:children)
      |> Enum.sort_by(& &1.sequence)

    assert Enum.map(copied, & &1.class) == ["slide-1", "slide-2", "slide-3"]
    assert copied |> Enum.map(& &1.id) |> Enum.uniq() |> length() == 3
    assert copied |> Enum.map(& &1.uid) |> Enum.uniq() |> length() == 3
    assert MapSet.disjoint?(MapSet.new(copied, & &1.id), MapSet.new(children, & &1.id))
    assert MapSet.disjoint?(MapSet.new(copied, & &1.uid), MapSet.new(children, & &1.uid))

    for {child, n} <- Enum.with_index(copied, 1) do
      assert Enum.map(child.vars, &{&1.key, &1.value}) == [{"title", "Title #{n}"}, {"kicker", "Kicker #{n}"}]
      assert Enum.all?(child.vars, &(&1.module_id == child.id))
      assert Enum.all?(child.refs, &(&1.module_id == child.id))
      expected_refs = if n == 2, do: ~w(body lede photo), else: ~w(body lede)
      assert Enum.map(child.refs, & &1.name) == expected_refs
    end

    # The picture ref keeps its image
    assert [%{image_id: image_id}] = Enum.filter(Enum.at(copied, 1).refs, &(&1.name == "photo"))
    assert image_id == image.id

    # Every ref uid is new and unique
    ref_uids = for child <- copied, ref <- child.refs, do: ref.uid
    original_uids = for child <- Repo.preload(children, :refs), ref <- child.refs, do: ref.uid
    assert length(Enum.uniq(ref_uids)) == 7
    assert MapSet.disjoint?(MapSet.new(ref_uids), MapSet.new(original_uids))

    # The originals keep their children, refs and vars
    original = Repo.preload(Repo.get!(Module, parent.id), children: [:vars, :refs])
    assert original.children |> Enum.map(& &1.id) |> Enum.sort() == Enum.map(children, & &1.id)
    assert original.children |> Enum.flat_map(& &1.vars) |> length() == 6
    assert original.children |> Enum.flat_map(& &1.refs) |> length() == 7
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

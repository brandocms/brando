defmodule Brando.Translations.UnloadedSchemaTest do
  # A Mix task, a release `eval` or a fresh node names a schema nothing has
  # loaded yet: what it exports is read after loading it.
  use ExUnit.Case, async: true

  alias Brando.Translations.Labels
  alias Brando.Translations.Sync

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    schema = Module.concat(__MODULE__, "Unloaded#{System.unique_integer([:positive])}")

    Brando.Test.UnloadedModule.compile(
      quote do
        defmodule unquote(schema) do
          def __blocks_fields__, do: [%{name: :blocks}]
        end
      end,
      dir
    )

    refute :code.is_loaded(schema)
    %{schema: schema}
  end

  defp block(attrs) do
    Map.merge(
      %{
        uid: "b1",
        sync_uid: nil,
        module_id: 5,
        module_origin: nil,
        module: %{name: "Text"},
        children: [],
        vars: [],
        block_identifiers: []
      },
      attrs
    )
  end

  test "Sync.module_refs/2 finds the blocks", %{schema: schema} do
    assert Sync.module_refs([%{entry_blocks: [%{block: block(%{})}]}], schema) == [{:local, 5}]
  end

  test "Labels.block_index/2 indexes the blocks", %{schema: schema} do
    assert %{"b1" => %{uid: "b1"}} = Labels.block_index(schema, %{entry_blocks: [%{block: block(%{})}]})
  end
end

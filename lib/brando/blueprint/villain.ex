defmodule Brando.Blueprint.Villain do
  @moduledoc false
  def maybe_cast_blocks(changeset, module, user, opts) do
    cast_blocks = Keyword.get(opts, :cast_blocks, false)
    blocks_fields = module.__blocks_fields__()

    if cast_blocks do
      Enum.reduce(blocks_fields, changeset, fn field, updated_changeset ->
        {block_module, assoc_field} = get_block_module_and_assoc_field(field, module)

        Ecto.Changeset.cast_assoc(updated_changeset, assoc_field, with: &block_module.changeset(&1, &2, user, true))
      end)
    else
      changeset
    end
  end

  defp get_block_module_and_assoc_field(field, module) do
    rel_module =
      field.name
      |> to_string()
      |> Macro.camelize()
      |> String.to_atom()

    block_module = Module.concat([module, rel_module])
    assoc_field = :"entry_#{field.name}"

    {block_module, assoc_field}
  end
end

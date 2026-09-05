defmodule Brando.Content.ModuleDiff do
  @moduledoc """
  Classifies the difference between two revisions of a module definition.

  Saving a module runs a migration across every block that uses it
  (`Brando.Content.Blocks.sync_module/2`). Some of those changes are harmless —
  a reworded help text, a tweak to the template code — and some silently rewrite
  or orphan editor content in every entry on the site.

  This module answers *what kind* of change a pending module save is, without
  touching the database and without deciding policy. Callers use it to decide
  whether to warn the editor (`destructive?/1`), whether the definition moved at
  all (`effective?/1`), and how to describe the change (`summary/1`).

  ## Classes

    * `:none` — nothing meaningful changed.
    * `:metadata` — name, namespace, help text, svg, colour, sequence. Blocks
      keep their data untouched.
    * `:render` — the template code or class changed but the ref/var contract did
      not. Blocks re-render; their data is untouched.
    * `:compatible` — refs or vars were added. Existing block data survives and
      the new ones are instantiated from the module.
    * `:destructive` — refs or vars were removed or retyped, or a contract field
      (multi, datasource, table template, module type) changed. Existing block
      data no longer has a definition behind it.

  The classes are ordered: `classify/1` returns the most severe one that applies.
  """

  alias Brando.Content.Module
  alias Brando.Villain.Blocks
  alias Ecto.Changeset

  defstruct added_refs: [],
            removed_refs: [],
            retyped_refs: [],
            added_vars: [],
            removed_vars: [],
            retyped_vars: [],
            contract_changes: [],
            metadata_changed?: false,
            code_changed?: false

  @type t :: %__MODULE__{
          added_refs: [String.t()],
          removed_refs: [String.t()],
          retyped_refs: [{String.t(), module(), module()}],
          added_vars: [String.t()],
          removed_vars: [String.t()],
          retyped_vars: [{String.t(), atom(), atom()}],
          contract_changes: [{atom(), term(), term()}],
          metadata_changed?: boolean(),
          code_changed?: boolean()
        }

  @type class :: :none | :metadata | :render | :compatible | :destructive

  @metadata_fields ~w(name namespace help_text svg color sequence)a

  # `class` sits with `code` rather than with the metadata: both feed the rendered
  # markup and neither touches a block's stored instance data.
  @render_fields ~w(code class)a

  # Fields that change what a block's stored instance data *means*, rather than
  # how it looks. `multi` decides whether a block owns child entries,
  # `table_template_id` reshapes table rows, and the datasource fields swap out
  # where a block's content comes from entirely.
  @contract_fields ~w(type multi datasource datasource_module datasource_type datasource_query table_template_id)a

  @doc """
  Diffs a persisted module against its pending revision.

  The second argument may be a `%Module{}` or a changeset on one — a changeset is
  applied first, so this works straight off an unsaved admin form.
  """
  @spec diff(Module.t(), Module.t() | Changeset.t()) :: t()
  def diff(%Module{} = old, %Changeset{} = changeset),
    do: diff(old, Changeset.apply_changes(changeset))

  def diff(%Module{} = old, %Module{} = new) do
    old_refs = ref_map(old)
    new_refs = ref_map(new)
    old_vars = var_map(old)
    new_vars = var_map(new)

    %__MODULE__{
      added_refs: sorted_keys(new_refs, old_refs),
      removed_refs: sorted_keys(old_refs, new_refs),
      retyped_refs: retyped(old_refs, new_refs, &ref_retyped?/2),
      added_vars: sorted_keys(new_vars, old_vars),
      removed_vars: sorted_keys(old_vars, new_vars),
      retyped_vars: retyped(old_vars, new_vars, &!=/2),
      contract_changes: contract_changes(old, new),
      metadata_changed?: any_field_changed?(old, new, @metadata_fields),
      code_changed?: any_field_changed?(old, new, @render_fields)
    }
  end

  @doc """
  True when the change orphans or reinterprets instance data that blocks already hold.
  """
  @spec destructive?(t()) :: boolean()
  def destructive?(%__MODULE__{} = diff) do
    diff.removed_refs != [] or diff.retyped_refs != [] or
      diff.removed_vars != [] or diff.retyped_vars != [] or
      diff.contract_changes != []
  end

  @doc """
  True when the module definition moved at all.

  A save that only rewords a `version_note`, or that persists no change beyond
  timestamps, is not an effective change and should not bump the module version.
  """
  @spec effective?(t()) :: boolean()
  def effective?(%__MODULE__{} = diff), do: classify(diff) != :none

  @doc "Returns the most severe class that applies to this diff."
  @spec classify(t()) :: class()
  def classify(%__MODULE__{} = diff) do
    cond do
      destructive?(diff) -> :destructive
      diff.added_refs != [] or diff.added_vars != [] -> :compatible
      diff.code_changed? -> :render
      diff.metadata_changed? -> :metadata
      true -> :none
    end
  end

  @doc """
  Human-readable lines describing every destructive part of the diff.

  Returns `[]` for a non-destructive diff. Used by the module editor's
  confirmation dialog, so the strings are deliberately concrete: an editor
  should be able to tell which of their references is about to be orphaned.
  """
  @spec summary(t()) :: [String.t()]
  def summary(%__MODULE__{} = diff) do
    Enum.concat([
      Enum.map(diff.removed_refs, &~s(Reference "#{&1}" was removed)),
      Enum.map(diff.retyped_refs, fn {name, from, to} ->
        ~s(Reference "#{name}" changed from #{ref_type_label(from)} to #{ref_type_label(to)})
      end),
      Enum.map(diff.removed_vars, &~s(Variable "#{&1}" was removed)),
      Enum.map(diff.retyped_vars, fn {key, from, to} ->
        ~s(Variable "#{key}" changed from #{from} to #{to})
      end),
      Enum.map(diff.contract_changes, fn {field, from, to} ->
        ~s("#{field}" changed from #{value_label(from)} to #{value_label(to)})
      end)
    ])
  end

  # Every block module answers `__block_type__/0` with the short name the editor
  # already knows the reference by ("picture", "text"), which beats printing the
  # fully qualified struct at someone deciding whether to save.
  defp ref_type_label(nil), do: "none"

  defp ref_type_label(struct) do
    if function_exported?(struct, :__block_type__, 0) do
      struct.__block_type__()
    else
      struct |> Elixir.Module.split() |> List.last()
    end
  end

  defp value_label(nil), do: "none"
  defp value_label(value) when is_binary(value), do: value
  defp value_label(value), do: inspect(value)

  defp ref_map(module) do
    module
    |> loaded_list(:refs)
    |> Map.new(&{&1.name, ref_type(&1)})
  end

  defp var_map(module) do
    module
    |> loaded_list(:vars)
    |> Map.new(&{&1.key, &1.type})
  end

  # A ref's type is the polymorphic embed it carries — swapping a picture ref for
  # a text ref keeps the name but makes the stored data meaningless.
  defp ref_type(%{data: %{__struct__: struct}}), do: struct
  defp ref_type(_ref), do: nil

  defp loaded_list(module, field) do
    case Map.get(module, field) do
      list when is_list(list) -> list
      _not_loaded_or_nil -> []
    end
  end

  defp sorted_keys(from, against) do
    from
    |> Map.keys()
    |> Enum.reject(&Map.has_key?(against, &1))
    |> Enum.sort()
  end

  defp retyped(old, new, changed?) do
    old
    |> Enum.sort()
    |> Enum.filter(fn {key, old_type} ->
      Map.has_key?(new, key) and changed?.(old_type, Map.fetch!(new, key))
    end)
    |> Enum.map(fn {key, old_type} -> {key, old_type, Map.fetch!(new, key)} end)
  end

  # A `media` ref is a slot that legitimately backs a picture, video, gallery or
  # svg block ref, so swapping between those is not a retype — see
  # `Brando.Villain.Blocks.ref_types_compatible?/2`. Anything else leaves the
  # block holding data the new definition cannot read.
  defp ref_retyped?(old_type, new_type) do
    not (Blocks.ref_types_compatible?(old_type, new_type) or
           Blocks.ref_types_compatible?(new_type, old_type))
  end

  defp contract_changes(old, new) do
    @contract_fields
    |> Enum.filter(&field_changed?(old, new, &1))
    |> Enum.map(&{&1, Map.get(old, &1), Map.get(new, &1)})
  end

  defp any_field_changed?(old, new, fields),
    do: Enum.any?(fields, &field_changed?(old, new, &1))

  defp field_changed?(old, new, field),
    do: unset(Map.get(old, field)) != unset(Map.get(new, field))

  # A module that has never had its `multi` checkbox touched stores `nil`, and
  # the form posts `false` the first time it is saved. Reading that as a change
  # of the multi contract put the destructive-change dialog in front of the
  # *first* save of every new module. `nil`, `false` and `""` all mean the same
  # thing here: the field was never set.
  defp unset(nil), do: nil
  defp unset(false), do: nil
  defp unset(""), do: nil
  defp unset(value), do: value
end

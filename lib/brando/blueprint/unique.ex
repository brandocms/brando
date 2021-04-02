defmodule Brando.Blueprint.Unique do
  alias Brando.Utils
  import Ecto.Changeset
  import Ecto.Query

  def run_unique_constraints(changeset, module, attributes) do
    attributes
    |> Enum.filter(&Map.get(&1.opts, :unique, false))
    |> Enum.reduce(changeset, fn
      %{opts: %{unique: true}} = f, new_changeset ->
        unique_constraint(new_changeset, f.name)

      %{opts: %{unique: [with: with_field]}} = f, new_changeset ->
        unique_constraint(new_changeset, [f.name, with_field])

      %{opts: %{unique: [prevent_collision: true]}} = f, new_changeset ->
        new_changeset
        |> Utils.Schema.avoid_field_collision(module, [f.name], nil)
        |> unique_constraint(f.name)

      %{opts: %{unique: [prevent_collision: filter_fn]}} = f, new_changeset
      when is_function(filter_fn) ->
        new_changeset
        |> Utils.Schema.avoid_field_collision(module, [f.name], filter_fn)
        |> unique_constraint(f.name)

      %{opts: %{unique: [prevent_collision: filter_field]}} = f, new_changeset ->
        new_changeset
        |> Utils.Schema.avoid_field_collision(
          module,
          [f.name],
          {filter_field, &filter_by_field/3}
        )
        |> unique_constraint([f.name, filter_field])
    end)
  end

  defp filter_by_field(module, field, changeset) do
    from m in module,
      where: field(m, ^field) == ^get_field(changeset, field)
  end
end

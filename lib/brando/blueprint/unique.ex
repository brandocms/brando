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
        |> Utils.Schema.avoid_field_collision([f.name])
        |> unique_constraint(f.name)

      %{opts: %{unique: [prevent_collision: :language]}} = f, new_changeset ->
        new_changeset
        |> Utils.Schema.avoid_field_collision(module, [f.name], &filter_by_language/2)
        |> unique_constraint([f.name, :language])
    end)
  end

  defp filter_by_language(module, changeset) do
    from m in module,
      where: m.language == ^get_field(changeset, :language)
  end
end

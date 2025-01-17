defmodule Brando.Blueprint.Unique do
  @moduledoc false
  import Ecto.Changeset
  import Ecto.Query

  alias Brando.Utils

  def run_unique_attribute_constraints(changeset, module, attributes) do
    attributes
    |> Enum.filter(&Map.get(&1.opts, :unique, false))
    |> Enum.reduce(changeset, fn
      %{opts: %{unique: true}} = f, new_changeset ->
        unique_constraint(new_changeset, f.name)

      %{opts: %{unique: [prevent_collision: true]}} = f, new_changeset ->
        new_changeset
        |> Utils.Schema.avoid_field_collision(module, [f.name], nil)
        |> unique_constraint(f.name)

      %{opts: %{unique: [prevent_collision: filter_fn]}} = f, new_changeset
      when is_function(filter_fn) ->
        new_changeset
        |> Utils.Schema.avoid_field_collision(module, [f.name], filter_fn)
        |> unique_constraint(f.name)

      %{opts: %{unique: [prevent_collision: filter_fields]}} = f, new_changeset
      when is_list(filter_fields) ->
        new_changeset
        |> Utils.Schema.avoid_field_collision(
          module,
          [f.name],
          {filter_fields, &filter_by_fields/3}
        )
        |> unique_constraint([f.name] ++ filter_fields)

      %{opts: %{unique: [prevent_collision: filter_field]}} = f, new_changeset ->
        new_changeset
        |> Utils.Schema.avoid_field_collision(
          module,
          [f.name],
          {filter_field, &filter_by_field/3}
        )
        |> unique_constraint([f.name, filter_field])

      %{opts: %{unique: unique_opts}} = f, new_changeset ->
        message = Keyword.get(unique_opts, :message, "has already been taken")

        case Keyword.get(unique_opts, :with) do
          nil ->
            nil

          with_fields when is_list(with_fields) ->
            unique_constraint(new_changeset, [f.name] ++ with_fields, message: message)

          with_field ->
            unique_constraint(new_changeset, [f.name, with_field], message: message)
        end
    end)
  end

  def run_unique_relation_constraints(changeset, _, relations) do
    relations
    |> Enum.filter(&Map.get(&1.opts, :unique, false))
    |> Enum.reduce(changeset, fn
      %{opts: %{unique: true}} = f, new_changeset ->
        unique_constraint(new_changeset, f.name)

      %{opts: %{unique: unique_opts}} = f, new_changeset ->
        message = Keyword.get(unique_opts, :message, "has already been taken")

        case Keyword.get(unique_opts, :with) do
          nil ->
            nil

          with_fields when is_list(with_fields) ->
            field = String.to_existing_atom("#{to_string(f.name)}_id")
            unique_constraint(new_changeset, [field] ++ with_fields, message: message)

          with_field ->
            field = String.to_existing_atom("#{to_string(f.name)}_id")
            unique_constraint(new_changeset, [field, with_field], message: message)
        end
    end)
  end

  defp filter_by_field(module, field, changeset) do
    from(m in module,
      where: field(m, ^field) == ^get_field(changeset, field)
    )
  end

  defp filter_by_fields(module, fields, changeset) do
    Enum.reduce(fields, from(m in module), fn field, query ->
      from q in query, where: field(q, ^field) == ^get_field(changeset, field)
    end)
  end
end

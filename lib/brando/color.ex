defmodule Brando.Color do
  @moduledoc """
  Validation for colour fields: every `:color` input in a Blueprint form
  (subforms included) and block vars of type `:color`.

  The colour picker stores hex (`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`).
  A CSS colour keyword (`transparent`) and colour functions (`rgb()`,
  `hsl()`, `oklch()`, `color-mix()`, `var(--brand)` and the like) written by
  hand or in a definition file are accepted too. Anything else is refused:
  the value is written into style attributes and stylesheets, and shown to
  other admins.
  """
  alias Ecto.Changeset

  @hex ~r/\A#(?:[[:xdigit:]]{3,4}|[[:xdigit:]]{6}|[[:xdigit:]]{8})\z/
  @keyword ~r/\A[a-z]+\z/i
  # A function's arguments: numbers, units, keywords, custom property names
  # and nested functions. No quotes, colons, semicolons, braces or escapes,
  # so a value cannot leave its declaration or attribute.
  @function ~r/\A[a-z][a-z-]*\([a-z0-9#.,%()\/\s+-]*\)\z/i
  @function_name ~r/([a-z-]*)\(/i
  @functions ~w(rgb rgba hsl hsla hwb lab lch oklab oklch color color-mix light-dark var)
  @max_length 200

  @message "is not a valid colour"

  @doc """
  Whether `value` is a colour a colour field may store. `nil` and `""` are
  (no colour).
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in [nil, ""], do: true

  def valid?(value) when is_binary(value) and byte_size(value) <= @max_length,
    do: Regex.match?(@hex, value) or Regex.match?(@keyword, value) or function?(value)

  def valid?(_), do: false

  defp function?(value) do
    Regex.match?(@function, value) and balanced?(value) and
      @function_name
      |> Regex.scan(value, capture: :all_but_first)
      |> Enum.all?(fn [name] -> String.downcase(name) in @functions end)
  end

  defp balanced?(value) do
    value
    |> String.graphemes()
    |> Enum.reduce_while(0, fn
      "(", depth -> {:cont, depth + 1}
      ")", 0 -> {:halt, -1}
      ")", depth -> {:cont, depth - 1}
      _, depth -> {:cont, depth}
    end)
    |> Kernel.==(0)
  end

  @doc """
  A stored var about to be copied into a new row (a module's default into a
  new block, a table template's into a new row), with a colour value stored
  before values were checked left empty. The copy is a new row, which the
  check would refuse, and the default is not the editor's to fix: the new
  block starts without the colour instead. `mix brando.doctor` lists these
  defaults.
  """
  @spec clear_invalid_var(var) :: var when var: map()
  def clear_invalid_var(%{type: :color, value: value} = var) do
    if valid?(value), do: var, else: %{var | value: nil}
  end

  def clear_invalid_var(var), do: var

  @doc """
  `value`, a stored record or a list of them (a decoded revision, say), with
  every colour that is not a valid colour left empty: the record's own
  `:color` fields (subform rows included) and colour vars at any depth (an
  entry's blocks, their children and table rows). Other records it holds,
  such as a ref's image, keep their colour fields: they are not the record's
  content. Returns the cleaned value and a description of each colour
  cleared.

  Restoring a revision uses it, so a colour stored before values were checked
  comes back empty rather than refusing the restore.
  """
  @spec clear_invalid(value) :: {value, [String.t()]} when value: term()
  def clear_invalid(value), do: clear(value, :own)

  defp clear(list, spec) when is_list(list) do
    {items, cleared} = list |> Enum.map(&clear(&1, spec)) |> Enum.unzip()
    {items, List.flatten(cleared)}
  end

  # Matched by name, without a compile-time dependency on the Blueprint
  defp clear(%{__struct__: Brando.Content.Var} = var, _spec) do
    case clear_invalid_var(var) do
      ^var -> {var, []}
      cleared -> {cleared, ["var #{var.key}: #{inspect(var.value)}"]}
    end
  end

  defp clear(%module{} = record, spec) do
    if function_exported?(module, :__schema__, 1) do
      spec = if spec == :own, do: color_fields(module), else: spec || []
      {record, cleared} = Enum.reduce(spec, {record, []}, &clear_field(&2, &1))

      (module.__schema__(:associations) ++ module.__schema__(:embeds))
      |> Enum.reduce({record, cleared}, fn name, {record, cleared} ->
        {children, child_cleared} = clear(Map.get(record, name), relation_spec(spec, name))
        {Map.put(record, name, children), cleared ++ child_cleared}
      end)
    else
      {record, []}
    end
  end

  defp clear(value, _spec), do: {value, []}

  defp clear_field({record, cleared}, field) when is_atom(field) do
    value = Map.get(record, field)

    if valid?(value),
      do: {record, cleared},
      else: {Map.put(record, field, nil), cleared ++ ["#{field}: #{inspect(value)}"]}
  end

  defp clear_field(acc, {_relation, _fields}), do: acc

  defp color_fields(module) do
    if function_exported?(module, :__color_fields__, 0), do: module.__color_fields__(), else: []
  end

  # A subform's rows take its colour fields; any other relation none
  defp relation_spec(spec, name) do
    Enum.find_value(spec, fn
      {^name, fields} -> fields
      _ -> nil
    end)
  end

  @doc """
  Validates the colour fields of `module`'s changeset. `validate_colors:
  false` in `opts` skips it, for re-reading records already stored.
  """
  @spec validate_blueprint(Changeset.t(), module(), keyword() | map()) :: Changeset.t()
  def validate_blueprint(changeset, module, opts \\ []) do
    if opts[:validate_colors] != false,
      do: validate_module(changeset, module),
      else: changeset
  end

  defp validate_module(changeset, Brando.Content.Var) do
    cond do
      Changeset.get_field(changeset, :type) != :color -> changeset
      # A var becoming a colour var brings its value along unchanged
      Map.has_key?(changeset.changes, :type) -> validate_current(changeset, :value)
      true -> validate(changeset, [:value])
    end
  end

  defp validate_module(changeset, module) do
    if function_exported?(module, :__color_fields__, 0),
      do: validate(changeset, module.__color_fields__()),
      else: changeset
  end

  @doc """
  Validates `fields`: field names, or `{relation, fields}` for the rows of
  a subform, which are cast into the changeset already. A row kept exactly
  as stored keeps its own colours: rows without a primary key (embeds) are
  cast as new on every save, so a value stored before this check comes back
  as a change. A row that changes is checked whole, and the rows of its own
  subforms are always checked the same way.
  """
  @spec validate(Changeset.t(), [atom() | {atom(), list()}]) :: Changeset.t()
  def validate(changeset, fields), do: validate(changeset, fields, changeset.data)

  # `data` is what the changeset's rows were stored as
  defp validate(changeset, fields, data), do: Enum.reduce(fields, changeset, &validate_field(&2, &1, data))

  defp validate_field(changeset, {relation, fields}, data) do
    stored = stored_rows(Map.get(data, relation))

    case Map.fetch(changeset.changes, relation) do
      {:ok, children} when is_list(children) ->
        children = Enum.map(children, &validate_child(&1, fields, stored))
        put_children(changeset, relation, children, Enum.all?(children, &child_valid?/1))

      {:ok, %Changeset{} = child} ->
        child = validate_child(child, fields, stored)
        put_children(changeset, relation, child, child.valid?)

      _ ->
        changeset
    end
  end

  defp validate_field(changeset, field, _data) do
    Changeset.validate_change(changeset, field, fn _, value ->
      if valid?(value), do: [], else: [{field, @message}]
    end)
  end

  defp stored_rows(rows) when is_list(rows), do: rows
  defp stored_rows(%Ecto.Association.NotLoaded{}), do: []
  defp stored_rows(%{} = row), do: [row]
  defp stored_rows(_), do: []

  # A row's own columns (embeds included), without its associations
  defp row_fields(%module{} = row), do: Map.take(row, module.__schema__(:fields))
  defp row_fields(row), do: row

  defp validate_current(changeset, field) do
    if valid?(Changeset.get_field(changeset, field)),
      do: changeset,
      else: Changeset.add_error(changeset, field, @message)
  end

  defp validate_child(%Changeset{} = child, fields, stored) do
    row = row_fields(Changeset.apply_changes(child))

    case Enum.find(stored, &(row_fields(&1) == row)) do
      nil -> validate(child, fields, child.data)
      kept -> validate(child, Enum.filter(fields, &is_tuple/1), kept)
    end
  end

  defp validate_child(child, _fields, _stored), do: child

  defp child_valid?(%Changeset{valid?: valid?}), do: valid?
  defp child_valid?(_), do: true

  defp put_children(changeset, relation, children, children_valid?) do
    %{changeset | changes: Map.put(changeset.changes, relation, children), valid?: changeset.valid? and children_valid?}
  end
end

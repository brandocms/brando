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
  a subform, which are cast into the changeset already. A row may keep a
  value one of the stored rows holds: rows without a primary key (embeds)
  are all cast as new, so their stored values come back as changes.
  """
  @spec validate(Changeset.t(), [atom() | {atom(), list()}], map()) :: Changeset.t()
  def validate(changeset, fields, stored \\ %{}),
    do: Enum.reduce(fields, changeset, &validate_field(&2, &1, stored))

  defp validate_field(changeset, {relation, fields}, _stored) do
    stored = stored_values(Map.get(changeset.data, relation), fields)

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

  defp validate_field(changeset, field, stored) do
    known = Map.get(stored, field, MapSet.new())

    Changeset.validate_change(changeset, field, fn _, value ->
      if valid?(value) or MapSet.member?(known, value), do: [], else: [{field, @message}]
    end)
  end

  defp stored_values(rows, fields) do
    rows =
      case rows do
        rows when is_list(rows) -> rows
        %Ecto.Association.NotLoaded{} -> []
        %{} = row -> [row]
        _ -> []
      end

    for field <- fields, is_atom(field), into: %{}, do: {field, MapSet.new(rows, &Map.get(&1, field))}
  end

  defp validate_current(changeset, field) do
    if valid?(Changeset.get_field(changeset, field)),
      do: changeset,
      else: Changeset.add_error(changeset, field, @message)
  end

  defp validate_child(%Changeset{} = child, fields, stored), do: validate(child, fields, stored)
  defp validate_child(child, _fields, _stored), do: child

  defp child_valid?(%Changeset{valid?: valid?}), do: valid?
  defp child_valid?(_), do: true

  defp put_children(changeset, relation, children, children_valid?) do
    %{changeset | changes: Map.put(changeset.changes, relation, children), valid?: changeset.valid? and children_valid?}
  end
end

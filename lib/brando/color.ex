defmodule Brando.Color do
  @moduledoc """
  Validation for colour fields: every `:color` input in a Blueprint form
  (subforms included) and block vars of type `:color`.

  The colour picker stores hex (`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`).
  `rgb()`, `rgba()`, `hsl()` and `hsla()` with numeric arguments, and a
  single CSS keyword such as `transparent`, are accepted as well, for values
  written by hand or imported. Anything else is refused: the value is written
  into style attributes and stylesheets, and shown to other admins.
  """
  alias Ecto.Changeset

  @hex ~r/\A#(?:[[:xdigit:]]{3,4}|[[:xdigit:]]{6}|[[:xdigit:]]{8})\z/
  @number "[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:%|deg|grad|rad|turn)?"
  @comma_function Regex.compile!("\\A(?:rgba?|hsla?)\\(\\s*#{@number}(?:\\s*,\\s*#{@number}){2,3}\\s*\\)\\z", "i")
  @space_function Regex.compile!(
                    "\\A(?:rgba?|hsla?)\\(\\s*#{@number}(?:\\s+#{@number}){2}(?:\\s*/\\s*#{@number})?\\s*\\)\\z",
                    "i"
                  )
  @keyword ~r/\A[a-z]+\z/i

  @message "is not a valid colour"

  @doc """
  Whether `value` is a colour a colour field may store. `nil` and `""` are
  (no colour).
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in [nil, ""], do: true

  def valid?(value) when is_binary(value) do
    Enum.any?([@hex, @comma_function, @space_function, @keyword], &Regex.match?(&1, value))
  end

  def valid?(_), do: false

  @doc """
  Validates the colour fields of `module`'s changeset.
  """
  @spec validate_blueprint(Changeset.t(), module()) :: Changeset.t()
  def validate_blueprint(changeset, Brando.Content.Var) do
    cond do
      Changeset.get_field(changeset, :type) != :color -> changeset
      # A var becoming a colour var brings its value along unchanged
      Map.has_key?(changeset.changes, :type) -> validate_current(changeset, :value)
      true -> validate(changeset, [:value])
    end
  end

  def validate_blueprint(changeset, module) do
    if function_exported?(module, :__color_fields__, 0),
      do: validate(changeset, module.__color_fields__()),
      else: changeset
  end

  @doc """
  Validates `fields`: field names, or `{relation, fields}` for the rows of
  a subform, which are cast into the changeset already.
  """
  @spec validate(Changeset.t(), [atom() | {atom(), list()}]) :: Changeset.t()
  def validate(changeset, fields), do: Enum.reduce(fields, changeset, &validate_field(&2, &1))

  defp validate_field(changeset, {relation, fields}) do
    case Map.fetch(changeset.changes, relation) do
      {:ok, children} when is_list(children) ->
        children = Enum.map(children, &validate_child(&1, fields))
        put_children(changeset, relation, children, Enum.all?(children, &child_valid?/1))

      {:ok, %Changeset{} = child} ->
        child = validate_child(child, fields)
        put_children(changeset, relation, child, child.valid?)

      _ ->
        changeset
    end
  end

  defp validate_field(changeset, field) do
    Changeset.validate_change(changeset, field, fn _, value ->
      if valid?(value), do: [], else: [{field, @message}]
    end)
  end

  defp validate_current(changeset, field) do
    if valid?(Changeset.get_field(changeset, field)),
      do: changeset,
      else: Changeset.add_error(changeset, field, @message)
  end

  defp validate_child(%Changeset{} = child, fields), do: validate(child, fields)
  defp validate_child(child, _fields), do: child

  defp child_valid?(%Changeset{valid?: valid?}), do: valid?
  defp child_valid?(_), do: true

  defp put_children(changeset, relation, children, children_valid?) do
    %{changeset | changes: Map.put(changeset.changes, relation, children), valid?: changeset.valid? and children_valid?}
  end
end

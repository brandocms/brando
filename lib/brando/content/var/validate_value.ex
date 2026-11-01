defmodule Brando.Content.Var.ValidateValue do
  @moduledoc """
  A `date` or `datetime` var's value is one, and a `select` var's value is one
  of its options. Only a changed value is checked, so a value stored before
  this check does not stop a save that leaves it alone. `Brando.Color` checks
  `color` vars.

  The options are the changeset's own. Where params must not supply them they
  have been held first (`Brando.Content.VarGuard`): a block's vars, and the
  Globals screen.

  As a trait it covers vars saved with their owner; block vars run
  `validate/1` in `Brando.Content.Block.var_changeset/3,4`.

  Only `Ecto.Changeset` is referenced: `Brando.Content.Var` depends on this
  trait at compile time.
  """
  use Brando.Trait

  alias Ecto.Changeset

  @message "is not a valid value"

  # `validate_var_values: false` skips it, for reading definitions: a stored
  # default whose option has gone must not stop a snapshot or an import.
  def changeset_mutator(_module, _config, changeset, _user, opts) do
    if opts[:validate_var_values] == false, do: changeset, else: validate(changeset)
  end

  @doc "Checks the changed value of a `date`, `datetime` or `select` var."
  @spec validate(Changeset.t()) :: Changeset.t()
  def validate(changeset) do
    type = Changeset.get_field(changeset, :type)
    options = Changeset.get_embed(changeset, :options, :struct)

    Changeset.validate_change(changeset, :value, fn :value, value ->
      if valid?(type, value, options), do: [], else: [value: @message]
    end)
  end

  @doc "`changeset` without this check's error, for a definition read as it is."
  @spec forget_error(Changeset.t()) :: Changeset.t()
  def forget_error(%Changeset{errors: errors} = changeset),
    do: %{changeset | errors: Enum.reject(errors, &match?({:value, {@message, _}}, &1))}

  @doc "`var` with its value empty when it is not valid for its type: for a copy of a stored var."
  def clear_invalid(%{type: type, value: value, options: options} = var) do
    if valid?(type, value, options), do: var, else: %{var | value: nil}
  end

  defp valid?(_type, value, _options) when value in [nil, ""], do: true
  defp valid?(:date, value, _options), do: match?({:ok, _}, Date.from_iso8601(value))

  defp valid?(:datetime, value, _options),
    do: match?({:ok, _, _}, DateTime.from_iso8601(value)) or match?({:ok, _}, NaiveDateTime.from_iso8601(value))

  defp valid?(:select, value, options), do: Enum.any?(options || [], &(&1.value == value))
  defp valid?(_type, _value, _options), do: true
end

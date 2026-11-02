defmodule Brando.Pages.Fragment.KeyFormat do
  @moduledoc """
  Holds a fragment's parent key and key to identifiers: letters, marks,
  digits, `_`, `-`, `.` and `/`, as a parent key can be a page's URI, and a
  space and parentheses, as a copy's key is "footer (copy)". A space can't
  come first or last.

  The check runs when a key changes, so a stored key that doesn't fit still
  saves; what prints a key escapes it.
  """
  use Brando.Trait
  use Gettext, backend: Brando.Gettext

  @format ~r/\A[\p{L}\p{M}\p{N}_.\/ ()-]*\z/u

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    Enum.reduce([:parent_key, :key], changeset, fn field, changeset ->
      Ecto.Changeset.validate_change(changeset, field, fn ^field, value -> error(field, value) end)
    end)
  end

  defp error(field, value) do
    cond do
      not Regex.match?(@format, value) ->
        [
          {field,
           {dgettext("pages_fragment", "can only hold letters, digits, spaces and _ - . / ( )"), validation: :format}}
        ]

      String.starts_with?(value, " ") or String.ends_with?(value, " ") ->
        [{field, {dgettext("pages_fragment", "can't start or end with a space"), validation: :format}}]

      true ->
        []
    end
  end
end

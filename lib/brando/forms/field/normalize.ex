defmodule Brando.Forms.Field.Normalize do
  @moduledoc """
  Prepares a `Brando.Forms.Field` changeset: turns the admin's `option_rows`
  into `option_values` and `option_labels`, and checks the key.

  A key names the field in submissions, so it must be safe as a parameter
  name and in templates: lowercase letters, digits and underscores, starting
  with a letter.
  """
  use Brando.Trait
  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset

  @key_format ~r/^[a-z][a-z0-9_]*$/

  # Before `validate_required`, so a key filled in here counts.
  @changeset_phase :before_validate_required

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    changeset
    |> put_option_rows()
    |> validate_format(:key, @key_format,
      message: gettext("use lowercase letters, digits and underscores, starting with a letter")
    )
  end

  defp put_option_rows(%{params: %{"option_rows_present" => _} = params} = changeset) do
    rows =
      params
      |> Map.get("option_rows", %{})
      |> rows()
      |> Enum.map(fn row -> {trim(row["value"]), row["label"] || ""} end)
      |> Enum.reject(fn {value, _label} -> value == "" end)
      |> Enum.uniq_by(&elem(&1, 0))

    changeset
    |> put_change(:option_values, Enum.map(rows, &elem(&1, 0)))
    |> put_change(:option_labels, Map.new(rows))
  end

  defp put_option_rows(changeset), do: changeset

  # Rows arrive as an index-keyed map; order them by index, not by key string.
  defp rows(rows) when is_map(rows) do
    rows
    |> Enum.sort_by(fn {index, _} -> position(index) end)
    |> Enum.map(&elem(&1, 1))
  end

  defp rows(rows) when is_list(rows), do: rows
  defp rows(_), do: []

  defp position(index) do
    case Integer.parse(to_string(index)) do
      {position, _} -> position
      :error -> 0
    end
  end

  defp trim(nil), do: ""
  defp trim(value), do: String.trim(value)
end

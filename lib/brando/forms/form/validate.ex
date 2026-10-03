defmodule Brando.Forms.Form.Validate do
  @moduledoc """
  Checks a `Brando.Forms.Form` changeset as a whole: every field key must be
  unique, since a submission stores its values by key; the page after sending
  must be a path or a web address; submissions are kept for at least a day;
  and a confirmation needs an email field to send it to.
  """
  use Brando.Trait
  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    changeset
    |> validate_unique_keys()
    |> validate_redirect_url()
    |> validate_number(:retention_days, greater_than: 0)
    |> validate_confirmation()
  end

  defp validate_unique_keys(changeset) do
    # Only a changed field list can introduce a duplicate, and reading it only
    # then avoids loading fields a changeset never touched.
    keys =
      changeset
      |> changed_fields()
      |> Enum.map(&get_field(&1, :key))
      |> Enum.reject(&is_nil/1)

    case keys -- Enum.uniq(keys) do
      [] ->
        changeset

      duplicates ->
        add_error(
          changeset,
          :fields,
          gettext("Two fields share the key %{keys}. Each field needs its own key.",
            keys: duplicates |> Enum.uniq() |> Enum.join(", ")
          )
        )
    end
  end

  defp validate_redirect_url(changeset) do
    validate_change(changeset, :redirect_url, fn :redirect_url, url ->
      if redirect_url?(url),
        do: [],
        else: [redirect_url: gettext("Enter a path starting with /, or an address starting with https://")]
    end)
  end

  @doc "Whether `url` is somewhere a form may send visitors: a path on the site, or a web address."
  def redirect_url?("/" <> rest), do: not String.starts_with?(rest, ["/", "\\"]) and not String.contains?(rest, [" "])

  def redirect_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        not String.contains?(url, [" "])

      _ ->
        false
    end
  end

  def redirect_url?(_url), do: false

  # Checked when either side changes: switching it on, or removing the field.
  defp validate_confirmation(changeset) do
    with true <- get_field(changeset, :confirmation),
         true <- Map.has_key?(changeset.changes, :confirmation) or Map.has_key?(changeset.changes, :fields),
         fields when is_list(fields) <- get_field(changeset, :fields),
         false <- Enum.any?(fields, &(&1.type == :email)) do
      add_error(changeset, :confirmation, gettext("Add an Email field to send a confirmation to."))
    else
      _ -> changeset
    end
  end

  defp changed_fields(changeset) do
    changeset.changes
    |> Map.get(:fields, [])
    |> Enum.reject(&(&1.action in [:replace, :delete]))
  end
end

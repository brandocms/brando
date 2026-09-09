defmodule Brando.MarkdownSources.Source do
  @moduledoc "A locally mirrored repository document. Secrets belong to its configured connection."
  use Ecto.Schema
  import Ecto.Changeset

  schema "content_markdown_sources" do
    field :name, :string
    field :connection, :string
    field :ref, :string, default: "refs/heads/main"
    field :path, :string
    field :enabled, :boolean, default: true
    field :latest_version_id, :integer
    field :last_checked_at, :utc_datetime_usec
    field :last_error, :string
    field :publication_sequence, :integer, default: 0
    field :publication_status, :string, default: "Not imported"
    field :build_id, :integer
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:name, :connection, :ref, :path, :enabled])
    |> validate_required([:name, :connection, :ref, :path])
    |> validate_length(:name, max: 160)
    |> validate_length(:path, max: 512)
    |> validate_length(:ref, max: 256)
    |> validate_format(:ref, ~r/\Arefs\/heads\/[A-Za-z0-9][A-Za-z0-9._\/-]*\z/)
    |> validate_change(:ref, fn :ref, value ->
      if String.contains?(value, ["..", "//", "@{"]) or String.ends_with?(value, ["/", ".", ".lock"]),
        do: [ref: "must be a valid branch ref"],
        else: []
    end)
    |> validate_change(:path, fn :path, value ->
      if valid_path?(value), do: [], else: [path: "must be a repository-relative Markdown file"]
    end)
    |> unique_constraint([:connection, :ref, :path])
    |> optimistic_lock(:lock_version)
  end

  def valid_path?(path) when is_binary(path) do
    Regex.match?(~r/\A[A-Za-z0-9_][A-Za-z0-9._\/ -]*\.(md|markdown)\z/i, path) and
      Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", ".."]))
  end

  def valid_path?(_), do: false
end

defmodule Brando.Sites.Site do
  @moduledoc """
  A site in Brando's public tenant registry.

  Site records always live in PostgreSQL's `public` schema. Content is still
  stored in `public` while tenancy is disabled; later phases use the site's key
  together with an environment key to select an isolated content schema.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Brando.Environments.Environment
  alias Brando.Sites.DeployConfig

  @schema_prefix "public"
  @timestamps_opts [type: :utc_datetime_usec]

  @statuses [:active, :suspended, :archived]
  @delivery_modes [:dynamic, :static]
  @key_format ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
  @language_format ~r/^[a-z][a-z0-9-]*$/

  @type t :: %__MODULE__{}

  schema "sites" do
    field :name, :string
    field :key, :string
    field :languages, {:array, :string}, default: []
    field :default_language, :string
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :archived_at, :utc_datetime_usec
    field :delivery_mode, Ecto.Enum, values: @delivery_modes, default: :dynamic

    embeds_one :deploy_config, DeployConfig, on_replace: :update

    has_many :environments, Environment

    timestamps()
  end

  @required_fields [:name, :key, :languages, :default_language, :status, :delivery_mode]
  @optional_fields [:archived_at]

  def changeset(site \\ %__MODULE__{}, attrs) do
    site
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> cast_embed(:deploy_config, with: &DeployConfig.changeset/2)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1)
    |> validate_format(:key, @key_format)
    |> validate_languages()
    |> validate_default_language()
    |> unique_constraint(:key)
  end

  def statuses, do: @statuses
  def delivery_modes, do: @delivery_modes

  defp validate_languages(changeset) do
    languages = get_field(changeset, :languages, [])

    cond do
      languages == [] ->
        add_error(changeset, :languages, "must contain at least one language")

      Enum.any?(languages, &(not is_binary(&1) or not Regex.match?(@language_format, &1))) ->
        add_error(changeset, :languages, "must contain lowercase language keys")

      Enum.uniq(languages) != languages ->
        add_error(changeset, :languages, "must not contain duplicates")

      true ->
        changeset
    end
  end

  defp validate_default_language(changeset) do
    languages = get_field(changeset, :languages, [])
    default_language = get_field(changeset, :default_language)

    if is_binary(default_language) and default_language not in languages do
      add_error(changeset, :default_language, "must be included in languages")
    else
      changeset
    end
  end
end

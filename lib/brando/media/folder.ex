defmodule Brando.Media.Folder do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "media_folders" do
    field :scope, :string
    field :name, :string
    field :path, :string

    # false for folders that hold media the site did not choose itself — see
    # `hidden_folder` on image and file configs. The media library, the
    # alt-text page and the pickers leave them out.
    field :library, :boolean, default: true

    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps()
  end

  @required_fields [:scope, :name, :path]
  @optional_fields [:parent_id, :library]

  def changeset(folder, attrs) do
    folder
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:scope, min: 1)
    |> validate_length(:name, min: 1)
    |> validate_length(:path, min: 1)
    |> foreign_key_constraint(:parent_id)
    |> unique_constraint([:scope, :path], name: :media_folders_scope_path_idx)
    |> unique_constraint([:scope, :parent_id, :name], name: :media_folders_scope_parent_name_idx)
  end
end

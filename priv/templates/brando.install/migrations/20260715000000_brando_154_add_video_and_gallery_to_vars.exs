defmodule Brando.Repo.Migrations.AddVideoAndGalleryToVars do
  use Ecto.Migration

  def change do
    alter table(:content_vars) do
      add :video_id, references(:videos, on_delete: :nilify_all)
      add :gallery_id, references(:galleries, on_delete: :nilify_all)
      add :gallery_image_config_target, :text
      add :gallery_video_config_target, :text
      add :gallery_allowed_types, {:array, :string}, default: ["image", "video"]
    end

    create index(:content_vars, [:video_id])
    create index(:content_vars, [:gallery_id])
  end
end

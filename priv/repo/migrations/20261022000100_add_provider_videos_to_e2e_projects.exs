defmodule BrandoIntegration.Repo.Migrations.AddProviderVideosToE2eProjects do
  use Ecto.Migration

  # Two video fields of the E2E Project blueprint: one uploading to Bunny (the
  # E2E app's fake) and one with uploads turned off
  # (video-provider-upload.spec.js).
  def change do
    alter table(:projects_projects) do
      add :bunny_video_id, references(:videos, on_delete: :nilify_all)
      add :no_upload_video_id, references(:videos, on_delete: :nilify_all)
    end
  end
end

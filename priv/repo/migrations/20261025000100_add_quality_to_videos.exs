defmodule BrandoIntegration.Repo.Migrations.AddQualityToVideos do
  use Ecto.Migration

  # Mirrors the brando_221 upgrade migration for the test schema.
  @moduledoc """
  `videos.quality`: whether the video plays streamed or as an MP4 at a
  resolution (`Brando.Videos.Playback`).
  """

  def change do
    alter table(:videos) do
      add :quality, :string
    end
  end
end

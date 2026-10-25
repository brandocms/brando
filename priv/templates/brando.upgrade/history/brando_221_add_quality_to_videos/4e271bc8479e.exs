defmodule Brando.Repo.Migrations.Brando221AddQualityToVideos do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `videos.quality` holds whether a video plays
  streamed over HLS or as an MP4 at a chosen resolution
  (`Brando.Videos.Playback`). Empty, the default, is Automatic.
  """

  def up do
    for prefix <- prefixes() do
      alter table(:videos, prefix: prefix) do
        add_if_not_exists :quality, :string
      end
    end
  end

  def down do
    for prefix <- prefixes() do
      alter table(:videos, prefix: prefix) do
        remove_if_exists :quality, :string
      end
    end
  end

  # Every site environment, or only the one named by the migrator's prefix:
  # `Brando.Environments.ArchiveUpgrade` runs this again in an archive
  # restored from before it ran.
  defp prefixes do
    case prefix() do
      "tenant_" <> _ = environment ->
        [environment]

      _ ->
        %{rows: rows} =
          repo().query!(
            "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
          )

        Enum.map(rows, &hd/1)
    end
  end
end

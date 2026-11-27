defmodule Brando.Repo.Migrations.Brando254ClearVideoPreloadFalse do
  use Ecto.Migration

  @moduledoc """
  In every site environment, clears a stored `preload = false` on videos, so
  they render lazy, Brando's default for a video since 0.55.

  A stored `false` came from the video form, which stored it on every save,
  from the video drawer before its rebuild, from a form field's defaults, or
  from an editor choosing Off: nothing tells these apart, so all are
  cleared. Blocks and gallery objects that leave the setting to the video
  turn lazy with it. To keep one video eager, set Lazy load to Off on it
  again after the upgrade.

  Meant to run once, at the upgrade: an Off chosen after a rollback is
  cleared again by a second `up`. `down` changes nothing, since a cleared
  value cannot be told from one that was always empty.
  """

  def up do
    for prefix <- prefixes(), table?(prefix, "videos") do
      execute(~s(UPDATE "#{prefix}".videos SET preload = NULL WHERE preload = false))
    end
  end

  def down, do: :ok

  defp table?(prefix, table) do
    %{rows: [[name]]} = repo().query!("SELECT to_regclass($1)::text", [~s("#{prefix}"."#{table}")])
    not is_nil(name)
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

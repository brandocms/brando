defmodule Brando.Repo.Migrations.Brando255ClearRefVideoPreloadFalse do
  use Ecto.Migration

  @moduledoc """
  In every site environment, clears a stored Lazy load Off (`preload =
  false`) on video refs and on media refs' video templates, in modules and
  in blocks, so their videos render lazy, the default.

  The module editor stored `false` on every save of a module with such a
  ref, and blocks made from it copied the module's ref. Nothing tells
  those apart from a developer's or an editor's Off, so all are cleared. To
  keep one eager, set Lazy load to Off on the ref again after the upgrade.
  Autoplay, Loop, Muted and Controls keep what is stored.

  Meant to run once, at the upgrade: an Off chosen after a rollback is
  cleared again by a second `up`. `down` changes nothing, since a cleared
  value cannot be told from one that was always empty.
  """

  def up do
    for prefix <- prefixes(), table?(prefix, "content_refs") do
      for {type, path} <- [
            {"video", "{data,preload}"},
            {"media", "{data,template_video,preload}"}
          ] do
        execute("""
        UPDATE "#{prefix}".content_refs SET data = jsonb_set(data, '#{path}', 'null')
        WHERE data->>'type' = '#{type}' AND data #> '#{path}' = 'false'
        """)
      end
    end
  end

  def down, do: :ok

  defp table?(prefix, table) do
    %{rows: [[name]]} =
      repo().query!("SELECT to_regclass($1)::text", [~s("#{prefix}"."#{table}")])

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

defmodule Brando.Environments.ArchiveUpgradeHistoryTest do
  # Restoring an archive replays a single-environment template only over an
  # application copy that is one of the versions Brando shipped of it
  # (`ArchiveUpgrade.shipped_versions/1`). Those versions are kept beside the
  # templates, and these tests keep them complete.
  use ExUnit.Case, async: true

  alias Brando.Environments.ArchiveUpgrade

  # The repository's own, so a failure names files to commit
  @root Path.expand("../../..", __DIR__)
  @templates Path.join(@root, "priv/templates/brando.upgrade/migrations")
  @history Path.join(@root, "priv/templates/brando.upgrade/history")

  defp hooked,
    do:
      for(
        template <- Path.wildcard(Path.join(@templates, "brando_*.exs")),
        File.read!(template) =~ ~r/case prefix\(\) do/,
        do: template
      )

  defp versions(template), do: template |> ArchiveUpgrade.shipped_versions() |> tl()

  defp relative(path), do: Path.relative_to(path, @root)

  test "every template with the replay hook keeps the version it is now" do
    assert length(hooked()) >= 12

    for template <- hooked() do
      source = File.read!(template)
      name = Path.basename(template, ".exs")
      file = :sha256 |> :crypto.hash(source) |> Base.encode16(case: :lower) |> binary_part(0, 12)

      assert Enum.any?(versions(template), &ArchiveUpgrade.same_code?(File.read!(&1), source)), """
      #{name}'s code is not one of its shipped versions in history/#{name}/.

      Applications keep the version of a migration they copied, and restoring an
      archive refuses a copy whose code is not a version Brando shipped. Keep the
      versions there as they are, and add this one:

          mkdir -p #{relative(Path.join(@history, name))}
          cp #{relative(template)} #{relative(Path.join([@history, name, file <> ".exs"]))}

      Docs, comments and layout do not count, so changing only those needs no new version.
      """
    end
  end

  test "every shipped version belongs to a template with the replay hook, once" do
    names = MapSet.new(hooked(), &Path.basename(&1, ".exs"))

    for directory <- Path.wildcard(Path.join(@history, "*")) do
      name = Path.basename(directory)
      assert name in names, "history/#{name} has no template with the replay hook"

      sources = for file <- Path.wildcard(Path.join(directory, "*.exs")), do: {Path.basename(file), File.read!(file)}

      for {file, source} <- sources do
        assert {:ok, _} = Code.string_to_quoted(source), "history/#{name}/#{file} does not parse"
      end

      for {file, source} <- sources, {other, other_source} <- sources, file < other do
        refute ArchiveUpgrade.same_code?(source, other_source),
               "history/#{name}/#{file} and #{other} are the same version; remove one"
      end
    end
  end

  test "the shipped versions are not taken for templates" do
    refute Enum.any?(Mix.Brando.Install.Templates.manifest(), fn {_, source, _} -> source =~ "history" end)
  end
end

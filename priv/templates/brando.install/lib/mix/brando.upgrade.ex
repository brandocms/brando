defmodule Mix.Tasks.Brando.Upgrade do
  use Mix.Task

  @shortdoc "Copies missing Brando migrations into the application"
  @moduledoc """
  Copies missing, versioned Brando migrations into `priv/repo/migrations`.

  Existing migrations are matched by their filename after the Ecto timestamp,
  so rerunning the task is safe. Missing migrations receive monotonically
  increasing, collision-free versions without starting the application or
  connecting to its database.
  """

  @impl Mix.Task
  def run(_argv) do
    app_migrations_dir = Path.join(["priv", "repo", "migrations"])
    File.mkdir_p!(app_migrations_dir)

    brando_migrations_dir =
      :brando
      |> Application.app_dir(["priv", "templates", "brando.upgrade", "migrations"])

    installed_migrations = installed_migration_names(app_migrations_dir)

    missing_migrations =
      brando_migrations_dir
      |> File.ls!()
      |> Enum.map(&parse_brando_migration!/1)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reject(fn {_sequence, filename} -> filename in installed_migrations end)

    copy_missing_migrations(missing_migrations, brando_migrations_dir, app_migrations_dir)
  end

  defp installed_migration_names(migrations_dir) do
    migrations_dir
    |> File.ls!()
    |> Enum.flat_map(fn filename ->
      case Regex.run(~r/^\d+_(.+\.exs)$/, filename, capture: :all_but_first) do
        [migration_name] -> [migration_name]
        nil -> []
      end
    end)
    |> MapSet.new()
  end

  defp parse_brando_migration!(filename) do
    case Regex.run(~r/^brando_(\d+)_.+\.exs$/, filename, capture: :all_but_first) do
      [sequence] -> {String.to_integer(sequence), filename}
      nil -> raise "invalid Brando migration template filename: #{filename}"
    end
  end

  defp copy_missing_migrations([], _source_dir, _target_dir) do
    Mix.shell().info([:green, "==> No missing Brando migrations found"])
  end

  defp copy_missing_migrations(migrations, source_dir, target_dir) do
    first_version = next_migration_version(target_dir)
    Mix.shell().info([:green, "==> Copying #{length(migrations)} missing Brando migration(s)"])

    migrations
    |> Enum.with_index()
    |> Enum.each(fn {{_sequence, filename}, offset} ->
      version = first_version + offset
      source = Path.join(source_dir, filename)
      target = Path.join(target_dir, "#{format_version(version)}_#{filename}")

      source
      |> EEx.eval_file()
      |> then(&File.write!(target, &1))

      Mix.shell().info("* #{Path.basename(target)}")
    end)
  end

  defp next_migration_version(migrations_dir) do
    current_version = DateTime.utc_now() |> Calendar.strftime("%Y%m%d%H%M%S") |> String.to_integer()

    latest_version =
      migrations_dir
      |> File.ls!()
      |> Enum.flat_map(fn filename ->
        case Integer.parse(filename) do
          {version, "_" <> _rest} -> [version]
          _ -> []
        end
      end)
      |> Enum.max(fn -> 0 end)

    max(current_version, latest_version + 1)
  end

  defp format_version(version) do
    version
    |> Integer.to_string()
    |> String.pad_leading(14, "0")
  end
end

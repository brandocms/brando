defmodule Mix.Tasks.Brando.Upgrade do
  use Mix.Task

  @moduledoc """
  Upgrade Brando.
  """

  @shortdoc "Checks and generates missing migrations"

  @doc """
  Copies Brando files from template and static directories to OTP app.
  """
  def run(_) do
    app = Mix.Project.config()[:app]

    Application.load(app)
    Application.ensure_all_started(app)

    Enum.map(Application.spec(app, :applications), &Application.load(&1))
    Enum.map(Application.spec(app, :applications), &Application.ensure_all_started(&1))

    app_migrations_dir = Path.join(["priv", "repo", "migrations"])

    brando_migrations_dir =
      Path.join([
        Application.app_dir(:brando),
        "priv",
        "templates",
        "brando.upgrade",
        "migrations"
      ])

    # list all brando upgrade migrations
    Mix.shell().info([:green, "\n==> Brando checking application's migration directory...\n"])
    {:ok, app_migrations} = File.ls(app_migrations_dir)

    app_migrations =
      app_migrations
      |> Enum.filter(&(&1 != ".formatter.exs"))
      |> Enum.map(&Regex.replace(~r/^(\d+\_)/, &1, ""))

    for m <- app_migrations do
      Mix.shell().info("* #{m}")
    end

    # list all application migrations
    Mix.shell().info([:green, "\n==> Brando checking BRANDO upgrade migration directory...\n"])

    {:ok, brando_migrations} = File.ls(brando_migrations_dir)
    brando_migrations = Enum.sort(brando_migrations)

    for m <- brando_migrations do
      Mix.shell().info("* #{m}")
    end

    # check what's missing
    missing_migrations = brando_migrations -- app_migrations
    Mix.shell().info([:green, "\n==> Finding missing migrations...\n"])

    for m <- missing_migrations do
      Mix.shell().info([:red, "* #{m}"])
    end

    if Enum.count(missing_migrations) > 0 do
      # copy migrations
      Mix.shell().info([:green, "\n==> Copying missing migrations...\n"])

      for m <- missing_migrations do
        src_file = Path.join([brando_migrations_dir, m])
        target_file = Path.join([app_migrations_dir, Enum.join([timestamp(), m], "_")])

        Mix.shell().info("* copying #{m} (#{timestamp()})")

        # try to run eex
        evaled_file = EEx.eval_file(src_file)
        :ok = File.write(target_file, evaled_file)

        # sleep here to not create dup files
        :timer.sleep(1500)
      end

      Mix.shell().info([:green, "\n==> Migration mirroring complete\n"])
    else
      Mix.shell().info([:green, "==> No missing migrations found!\n"])
    end
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)
end

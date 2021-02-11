defmodule Mix.Tasks.Brando.Gen.Release do
  use Mix.Task

  @shortdoc "Generates an Elixir release template"

  @moduledoc """
  Generates an Elixir release template

      mix brando.gen.release

  """
  @spec run(any) :: no_return
  def run(_) do
    Mix.shell().info("""
    % Brando release tpl generator
    ---------------------------------------

    """)

    app = Mix.Project.config()[:app]

    binding = [
      application_module: Phoenix.Naming.camelize(Atom.to_string(app)),
      application_name: Atom.to_string(app),
      secret_key_base: random_string(64),
      signing_salt: random_string(8),
      lv_signing_salt: random_string(8)
    ]

    Mix.shell().yes?("""
    This task will overwrite

      - your envrc files
      - your config files
      - your dockerfile
      - your fabfile
      - your supervisor cfg

    Be sure to commit your changes BEFORE running, then cherry pick these changes.

    Are you sure you want to continue?
    """)

    files = [
      {:copy, "gitignore", ".gitignore"},
      {:copy, "dockerignore", ".dockerignore"},
      {:eex, ".envrc", ".envrc"},
      {:eex, ".envrc.prod", ".envrc.prod"},
      {:eex, ".envrc.staging", ".envrc.staging"},
      {:eex, "rel/env.sh.eex", "rel/env.sh.eex"},
      {:eex, "rel/vm.args.eex", "rel/vm.args.eex"},
      {:eex, "lib/application_name/release_tasks.ex", "lib/application_name/release_tasks.ex"},
      {:copy, "Dockerfile", "Dockerfile"},
      {:copy, "fabfile.py", "fabfile.py"},
      {:eex, "config/config.exs", "config/config.exs"},
      {:eex, "config/dev.exs", "config/dev.exs"},
      {:eex, "config/e2e.exs", "config/e2e.exs"},
      {:eex, "config/prod.exs", "config/prod.exs"},
      {:eex, "config/staging.exs", "config/staging.exs"},
      {:eex, "config/runtime.exs", "config/runtime.exs"},
      {:eex, "etc/supervisord/prod.conf", "etc/supervisord/prod.conf"},
      {:eex, "etc/supervisord/staging.conf", "etc/supervisord/staging.conf"}
    ]

    Mix.Brando.copy_from(apps(), "priv/templates/brando.install", "", binding, files)

    Mix.shell().info([:green, "\n==> Add to mix.exs under `project`:\n"])

    Mix.shell().info("""
        releases: [
          #{binding[:application_name]}: [
            include_executables_for: [:unix],
            steps: [:assemble, :tar]
          ]
        ]
    """)
  end

  defp apps do
    [".", :brando]
  end

  defp random_string(length) do
    :crypto.strong_rand_bytes(length) |> Base.encode64() |> binary_part(0, length)
  end
end

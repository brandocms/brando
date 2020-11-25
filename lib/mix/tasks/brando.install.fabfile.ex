defmodule Mix.Tasks.Brando.Install.Fabfile do
  use Mix.Task

  @shortdoc "Copy fabfile and pgbackup"

  @moduledoc """
  Copy fabfile and pgbackup

      mix brando.install.fabfile

  """
  @spec run(any) :: no_return
  def run(_) do
    Mix.shell().info("""
    % Brando fabfile + pgbackup copy
    -------------------------------

    """)

    app = Mix.Project.config()[:app]

    binding = [
      application_module: Phoenix.Naming.camelize(Atom.to_string(app)),
      application_name: Atom.to_string(app)
    ]

    files = [
      {:copy, "fabfile.py", "fabfile.py"},
      {:eex, "etc/pgbkup.sh", "etc/pgbkup.sh"}
    ]

    Mix.Brando.copy_from(apps(), "priv/templates/brando.install", "", binding, files)
  end

  defp apps do
    [".", :brando]
  end
end

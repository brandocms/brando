defmodule Mix.Tasks.Brando.Gen.Authorization do
  use Mix.Task

  @shortdoc "Generates an authorization module template"

  @moduledoc """
  Generates an authorization module template

      mix brando.gen.authorization

  """
  @spec run(any) :: no_return
  def run(_) do
    Mix.shell().info("""
    % Brando Authorization module generator
    ---------------------------------------

    """)

    app = Mix.Project.config()[:app]

    binding = [
      application_module: Phoenix.Naming.camelize(Atom.to_string(app)),
      application_name: Atom.to_string(app)
    ]

    files = [
      {:eex, "lib/application_name/authorization.ex", "lib/application_name/authorization.ex"}
    ]

    Mix.Brando.copy_from(apps(), "priv/templates/brando.install", "", binding, files)
  end

  defp apps do
    [".", :brando]
  end
end

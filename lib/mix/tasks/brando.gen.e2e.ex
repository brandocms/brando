defmodule Mix.Tasks.Brando.Gen.E2e do
  use Mix.Task

  @shortdoc "Generates an E2E testing template"

  @moduledoc """
  Generates an E2E testing template

      mix brando.gen.e2e

  """
  @spec run(any) :: no_return
  def run(_) do
    Mix.shell().info("""
    % Brando E2E testing tpl generator
    ---------------------------------------

    """)

    app = Mix.Project.config()[:app]

    binding = [
      application_module: Phoenix.Naming.camelize(Atom.to_string(app)),
      application_name: Atom.to_string(app)
    ]

    files = [
      # E2E w/CYPRESS
      {:eex, "test_helper.exs", "test/e2e/test_helper.exs"},
      {:copy, "cypress.json", "e2e/cypress.json"},
      {:copy, "package.json", "e2e/package.json"},
      {:copy, "cypress/fixtures/avatar.jpg", "e2e/cypress/fixtures/avatar.jpg"},
      {:copy, "cypress/support/index.js", "e2e/cypress/support/index.js"},
      {:copy, "cypress/support/commands.js", "e2e/cypress/support/commands.js"},
      {:copy, "cypress/integration/Brando/Brando.spec.js",
       "e2e/cypress/integration/Brando/Brando.spec.js"}
    ]

    Mix.Brando.copy_from(apps(), "priv/templates/brando.gen.e2e", "", binding, files)

    Mix.shell().info("""
    Add to your router:

    @sql_sandbox Application.get_env(:<%= Atom.to_string(app) %>, :sql_sandbox) || false

    if @sql_sandbox do
      forward "/__e2e", Brando.Plug.E2ETest
    end

    """)
  end

  defp apps do
    [".", :brando]
  end
end

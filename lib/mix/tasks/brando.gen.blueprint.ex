defmodule Mix.Tasks.Brando.Gen.Blueprint do
  use Mix.Task

  @shortdoc "Generates a blueprint module template"

  @moduledoc """
  Generates a blueprint module template

      mix brando.gen.blueprint

  """
  @spec run(any) :: no_return
  def run(_) do
    Mix.shell().info("""
    % Brando Blueprint module generator
    ---------------------------------------

    """)

    app = Mix.Project.config()[:app]

    domain = Mix.shell().prompt("+ Enter domain") |> String.trim("\n")
    schema = Mix.shell().prompt("+ Enter schema") |> String.trim("\n")

    binding = [
      app_module: to_string(Brando.config(:app_module)) |> String.replace("Elixir.", ""),
      domain: domain,
      schema: schema,
      application_name: Atom.to_string(app)
    ]

    files = [
      {:eex, "blueprint.ex",
       "lib/application_name/#{Recase.to_snake(domain)}/#{Recase.to_snake(schema)}.ex"}
    ]

    Mix.Brando.copy_from(apps(), "priv/templates/brando.gen.blueprint", "", binding, files)
  end

  defp apps do
    [".", :brando]
  end
end

defmodule Mix.Tasks.Brando.Gen.Blueprint do
  @shortdoc "Generates a blueprint module template"

  @moduledoc """
  Generates a blueprint module template

      mix brando.gen.blueprint

  """
  use Mix.Task

  @spec run(any) :: no_return
  def run(_) do
    Mix.shell().info("""
    % Brando Blueprint module generator
    ---------------------------------------

    """)

    app = Mix.Project.config()[:app]

    domain = "+ Enter domain" |> Mix.shell().prompt() |> String.trim("\n")
    schema = "+ Enter schema" |> Mix.shell().prompt() |> String.trim("\n")

    binding = [
      app_module: :app_module |> Brando.config() |> to_string() |> String.replace("Elixir.", ""),
      domain: domain,
      schema: schema,
      application_name: Atom.to_string(app)
    ]

    files = [
      {:eex, "blueprint.ex", "lib/application_name/#{Macro.underscore(domain)}/#{Macro.underscore(schema)}.ex"}
    ]

    Mix.Brando.copy_from(apps(), "priv/templates/brando.gen.blueprint", "", binding, files)
  end

  defp apps do
    [".", :brando]
  end
end

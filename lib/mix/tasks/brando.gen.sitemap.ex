defmodule Mix.Tasks.Brando.Gen.Sitemap do
  @shortdoc "Generates a sitemap module template"

  @moduledoc """
  Generates a sitemap module template

      mix brando.gen.sitemap

  """
  use Mix.Task

  @spec run(any) :: no_return
  def run(_) do
    Mix.shell().info("""
    % Brando Sitemap module generator
    ---------------------------------------

    """)

    app = Mix.Project.config()[:app]

    binding = [
      web_module: :web_module |> Brando.config() |> to_string() |> String.replace("Elixir.", ""),
      application_name: Atom.to_string(app)
    ]

    files = [
      {:eex, "lib/application_name_web/sitemap.ex", "lib/application_name_web/sitemap.ex"}
    ]

    Mix.Brando.copy_from(apps(), "priv/templates/brando.gen.sitemap", "", binding, files)
  end

  defp apps do
    [".", :brando]
  end
end

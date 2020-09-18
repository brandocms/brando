defmodule Mix.Tasks.Brando.Gen.Sitemap do
  use Mix.Task

  @shortdoc "Generates a sitemap module template"

  @moduledoc """
  Generates a sitemap module template

      mix brando.gen.sitemap

  """
  @spec run(any) :: no_return
  def run(_) do
    Mix.shell().info("""
    % Brando Sitemap module generator
    ---------------------------------------

    """)

    app = Mix.Project.config()[:app]

    binding = [
      web_module: to_string(Brando.config(:web_module)) |> String.replace("Elixir.", ""),
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

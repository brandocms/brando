defmodule Mix.Tasks.Brando.Check.ImageTexts do
  use Mix.Task

  import Ecto.Query, only: [from: 2]

  alias Brando.Images.TextUsage

  @shortdoc "Finds templates that print an image's texts without choosing a language"

  @moduledoc """
  Finds module, container and navigation menu templates that print an image's
  `alt`, `title` or `credits` as if it were a string.

      mix brando.check.image_texts

  Since Brando 0.55 those fields are maps of language → text. Templates live
  in the database, where `mix brando.migrate55` cannot see them, so this task
  reads them — in every environment of every active site when tenancy is
  enabled. It changes nothing.

  In Liquid, add the `i18n` filter, which prints the page's language and
  falls back to the default; it leaves plain strings alone, so it is safe
  before and after the upgrade:

      {{ entry.cover.alt | i18n }}

  In HEEx templates, use `Brando.Images.text(image, :alt, @language)`.
  `{% picture %}` and `<.picture>` need nothing.

  Matching is by name — a project's image asset fields and the usual image
  variable names — so check each finding, and remember it can miss an image
  reached through a name it does not know.
  """

  @impl Mix.Task
  def run(_args) do
    Application.put_env(:logger, :level, :error)
    Mix.Tasks.Run.run([])

    assets = TextUsage.image_assets()

    findings =
      :all
      |> Brando.Tenant.Job.each_active_environment(fn -> scan(assets) end)
      |> List.flatten()

    report(findings)
  end

  @doc false
  def scan(assets) do
    environment = Brando.Tenant.current_prefix()

    templates()
    |> Enum.flat_map(fn {kind, name, type, code} ->
      scanner = if type == :heex, do: &TextUsage.scan_code/2, else: &TextUsage.scan_liquid/2

      code
      |> to_string()
      |> scanner.(assets)
      |> Enum.map(&Map.merge(&1, %{kind: kind, name: name, environment: environment}))
    end)
  end

  defp templates do
    modules =
      Brando.Repo.all(
        from m in Brando.Content.Module,
          where: is_nil(m.deleted_at),
          select: {m.name, m.type, m.code}
      )
      |> Enum.map(fn {name, type, code} -> {"Module", Brando.Type.I18nString.get(name, nil), type, code} end)

    containers =
      Brando.Repo.all(from c in Brando.Content.Container, where: is_nil(c.deleted_at), select: {c.name, c.type, c.code})
      |> Enum.map(fn {name, type, code} -> {"Container", name, type, code} end)

    menus =
      Brando.Repo.all(from m in Brando.Navigation.Menu, where: not is_nil(m.template), select: {m.key, m.template})
      |> Enum.map(fn {key, template} -> {"Menu", key, :liquid, template} end)

    modules ++ containers ++ menus
  end

  defp report([]) do
    Mix.shell().info([:green, "No template prints an image's alt text, title or credits without a language."])
  end

  defp report(findings) do
    Mix.shell().info([:yellow, "These templates print an image's alt text, title or credits as a string:\n"])

    for finding <- findings do
      where = if finding.environment, do: " [#{finding.environment}]", else: ""
      Mix.shell().info("  #{finding.kind} #{inspect(finding.name)}#{where}, line #{finding.line}: #{finding.text}")
    end

    Mix.shell().info("""

    In Liquid, add the i18n filter: {{ entry.cover.alt | i18n }}
    In HEEx, use Brando.Images.text(image, :alt, @language).
    Matched by name — check each one.
    """)
  end
end

defmodule Mix.Tasks.Brando.Fragments.Pair do
  @shortdoc "Link fragments that share their keys as each other's language versions"

  @moduledoc """
  Links fragments with the same parent key and key in different languages
  as each other's language versions (alternates), the way **Select entries
  to link** in the fragment form links them.

      mix brando.fragments.pair
      mix brando.fragments.pair --apply
      mix brando.fragments.pair --site acme --environment production --apply

  Without `--apply` it changes nothing: it lists the keys it would link and
  the ones it cannot. It cannot link a key that two fragments hold in one
  language, nor one held by a fragment already linked to another fragment
  (with other keys, or in the trash): an editor sorts those out in the
  fragment form. A key held in one language only has nothing to link.
  Fragments in the trash are left out.

  `--apply` checks each key again before it links it, all of its links in
  one transaction: a fragment renamed, trashed or linked by an editor since
  the list was made leaves its key as it is, and is reported. A link left
  one way is completed. Run it again at any time: linked keys are left as
  they are.

  Linking copies no content, and a linked translation stays independent; see
  "Synchronized fragments" in the i18n guide for synchronizing fragments.

  Tenant applications name the site and environment with `--site KEY
  --environment KEY`; standalone applications omit both. The list and the
  links are of that environment only.
  """
  use Mix.Task

  alias Brando.Pages.Fragment
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Translations.Pairing

  @switches [apply: :boolean, site: :string, environment: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches)
    Mix.Task.run("app.start")
    prefix = context!(opts)

    Tenant.with_prefix(prefix, fn ->
      plan = Pairing.plan(Fragment)
      report_plan(plan)
      if opts[:apply], do: plan |> then(&Pairing.apply(Fragment, &1)) |> report_apply(), else: hint(plan)
    end)
  end

  defp context!(opts) do
    if Tenant.mode() == :none do
      if opts[:site] || opts[:environment], do: Mix.raise("Site/environment options require tenant mode")
      nil
    else
      site_key = opts[:site] || Mix.raise("--site is required")
      environment_key = opts[:environment] || Mix.raise("--environment is required")
      site = Registry.get_site_by_key(site_key) || Mix.raise("Unknown site #{site_key}")

      environment =
        Registry.get_environment_by_key(site, environment_key) || Mix.raise("Unknown environment #{environment_key}")

      Tenant.prefix(site, environment)
    end
  end

  defp report_plan(plan) do
    groups = Enum.group_by(plan, & &1.status)

    section("To link", groups[:link], fn group -> "#{key(group)}: #{languages(group)}" end)

    section("Cannot link: two fragments in one language", groups[:same_language], fn group ->
      "#{key(group)}: #{Enum.map_join(group.entries, ", ", &"#{&1.language} ##{&1.id}")}"
    end)

    section("Cannot link: a fragment is linked to another fragment", groups[:linked_elsewhere], fn group ->
      "#{key(group)}: #{Enum.map_join(group.links, ", ", fn {a, b} -> "##{a} → ##{b}" end)}"
    end)

    section("In one language only", groups[:one_language], fn group -> "#{key(group)}: #{languages(group)}" end)

    Mix.shell().info("Already linked: #{length(groups[:linked] || [])} key(s)")
  end

  defp hint(plan) do
    if Enum.any?(plan, &(&1.status == :link)), do: Mix.shell().info("\nNothing changed. Run with --apply to link them.")
  end

  defp report_apply(results) do
    {linked, changed} = Enum.split_with(results, &(&1.status == :linked))
    section("Changed since the list was made, left as they are", changed, &key/1)
    Mix.shell().info("\nLinked #{length(linked)} key(s).")
  end

  defp section(_title, nil, _line), do: :ok

  defp section(title, groups, line) do
    Mix.shell().info("\n#{title} (#{length(groups)}):")
    Enum.each(groups, &Mix.shell().info("  " <> line.(&1)))
  end

  defp key(%{values: [parent_key, key]}), do: "#{parent_key}/#{key}"
  defp languages(group), do: Enum.map_join(group.entries, ", ", &"#{&1.language} ##{&1.id}")
end

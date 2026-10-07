defmodule Brando.Doctor.Checks.Migrations do
  @moduledoc """
  Migrations that have not run: the application's own, the copies of Brando's
  upgrade migrations, and the tenant migrations of every environment.

  Also lists what `mix brando.migrations.check` lists (pending copies of
  Brando's upgrade migrations that no longer match their templates), and
  upgrade migrations Brando has added since they were last copied
  (`mix brando.gen.migrations`).
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context
  alias Brando.Migration.TemplateDrift

  @impl true
  def id, do: "migrations"

  @impl true
  def label, do: dgettext("doctor", "Migrations")

  @impl true
  def run(_context) do
    repo = Brando.Repo.repo()
    directory = Ecto.Migrator.migrations_path(repo)
    statuses = statuses(repo, directory, [])
    public = for {:down, version, name} <- statuses, do: {version, name}

    evaluate(%{
      public: public,
      tenants: tenant_pending(repo),
      drift: TemplateDrift.check(directory, MapSet.new(public, &elem(&1, 0))),
      missing: missing_templates(directory),
      ran: Enum.count(statuses, &(elem(&1, 0) == :up))
    })
  end

  @doc """
  Turns what was found into a result. `findings` has `:public` and `:tenants`
  (`[{version, name}]` and `[{label, [{version, name}]}]`), `:drift`
  (`Brando.Migration.TemplateDrift` findings), `:missing` (template names) and
  `:ran`, the number already run.
  """
  def evaluate(findings) do
    public = findings.public
    tenant_count = findings.tenants |> Enum.map(fn {_label, pending} -> length(pending) end) |> Enum.sum()
    pending_count = length(public) + tenant_count

    items =
      Enum.map(public, fn {version, name} -> "#{version}_#{name}" end) ++
        Enum.flat_map(findings.tenants, fn {label, pending} ->
          Enum.map(pending, fn {version, name} -> Context.label_item(label, "#{version}_#{name}") end)
        end) ++
        Enum.map(findings.drift, &drift_item/1) ++
        Enum.map(findings.missing, &dgettext("doctor", "not copied: %{name}", name: &1))

    cond do
      pending_count > 0 ->
        error(
          dngettext("doctor", "%{count} migration not run", "%{count} migrations not run", pending_count),
          fix: pending_fix(public, tenant_count),
          items: items
        )

      findings.drift != [] ->
        warning(
          dngettext(
            "doctor",
            "%{count} upgrade migration differs from Brando's template",
            "%{count} upgrade migrations differ from Brando's templates",
            length(findings.drift)
          ),
          fix: dgettext("doctor", "run mix brando.migrations.check --update and review the diff"),
          items: items
        )

      findings.missing != [] ->
        warning(
          dngettext(
            "doctor",
            "%{count} new Brando migration not copied",
            "%{count} new Brando migrations not copied",
            length(findings.missing)
          ),
          fix: dgettext("doctor", "run mix brando.gen.migrations, then mix brando.migrate"),
          items: items
        )

      true ->
        ok(dgettext("doctor", "up to date"), items: [dngettext("doctor", "%{count} run", "%{count} run", findings.ran)])
    end
  end

  defp pending_fix([], _tenant_count), do: dgettext("doctor", "run mix brando.migrate --tenants")
  defp pending_fix(_public, 0), do: dgettext("doctor", "run mix brando.migrate")

  defp pending_fix(_public, _tenant_count),
    do: dgettext("doctor", "run mix brando.migrate, then mix brando.migrate --tenants")

  defp drift_item({:outdated, path, template}),
    do:
      dgettext("doctor", "%{file} differs from %{template}", file: Path.basename(path), template: Path.basename(template))

  defp drift_item({:renumbered, path, template}),
    do: dgettext("doctor", "%{file} is now %{template}", file: Path.basename(path), template: Path.basename(template))

  defp statuses(repo, directory, opts) do
    if File.dir?(directory), do: Ecto.Migrator.migrations(repo, [directory], opts), else: []
  end

  defp pending(repo, directory, opts),
    do: for({:down, version, name} <- statuses(repo, directory, opts), do: {version, name})

  defp tenant_pending(repo) do
    if Brando.Tenant.enabled?() do
      directory = Brando.Environments.Migrator.migrations_path()

      for site <- Brando.Tenant.Registry.list_sites(),
          environment <- Enum.sort_by(site.environments, & &1.id),
          pending = pending(repo, directory, prefix: Brando.Tenant.prefix(site, environment)),
          pending != [],
          do: {"#{site.key}/#{environment.key}", pending}
    else
      []
    end
  end

  # Brando's upgrade migrations not copied into the project. Only for projects
  # that copy them at all: one built on a single schema migration (like
  # Brando's own test project) has no `*_brando_*` files.
  @doc false
  def missing_templates(directory, templates_dir \\ TemplateDrift.templates_dir()) do
    copies = directory |> Path.join("*_brando_*.exs") |> Path.wildcard() |> Enum.map(&Path.basename/1)

    if copies == [] do
      []
    else
      copied = MapSet.new(copies, &String.replace(&1, ~r/^\d+_/, ""))
      suffixes = MapSet.new(copied, &suffix/1)

      templates_dir
      |> Path.join("brando_*.exs")
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)
      |> Enum.reject(&(MapSet.member?(copied, &1) or MapSet.member?(suffixes, suffix(&1))))
      |> Enum.sort()
    end
  end

  defp suffix(name), do: String.replace(name, ~r/^brando_\d+_/, "")
end

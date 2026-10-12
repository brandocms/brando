defmodule Mix.Tasks.Brando.Gettext.Reconcile do
  use Mix.Task

  alias Mix.Brando.GettextReconcile

  @shortdoc "Extracts, merges and tidies the application's Gettext catalogs after an upgrade"

  @moduledoc """
  Reconciles the application's Gettext catalogs with its source, the last
  step of an upgrade from 0.53 or 0.54:

      mix brando.gettext.reconcile
      mix brando.gettext.reconcile --dry-run

  It does, in one step, what the upgrade guide used to list as commands:

    1. Extracts the messages, as `mix gettext.extract` does, and updates the
       `.pot` files of each Gettext backend in the application.
    2. Merges each backend's existing locales, and only those, as
       `mix gettext.merge <priv dir> --locale <locale>` does. A locale's new
       catalogs get the `Plural-Forms` header its other catalogs declare, or
       the one Gettext knows for the locale, or `nplurals=2; plural=(n != 1);`.
    3. Fills each empty translation from a sibling catalog of the same locale
       that translates the same msgid, as `scripts/sync_gettext.sh` does:
       singular messages without context on one line only. The catalogs as
       they were before the merge count as siblings too, so a translation the
       merge dropped from `default` still fills a Blueprint domain.
    4. Deletes the 0.53 Blueprint domains (`<domain>_<schema>_naming`,
       `_forms`, `_listings`), `.pot` and `.po`, that hold no messages after
       the merge. `mix brando.migrate55` has already copied their
       translations into `<domain>_<schema>`.

  It then reports, per Blueprint domain and locale, the translations carried
  over, the ones filled from a sibling, and the ones dropped because their
  msgid is no longer in the source (listed), and how many messages are left
  untranslated.

    * `--dry-run` computes and reports everything, and writes nothing.

  Review the catalog diff before committing.
  """

  @switches [dry_run: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, _positional} = Mix.Brando.parse_options!("brando.gettext.reconcile", args, @switches)
    dry_run? = opts[:dry_run] == true

    Application.ensure_all_started(:gettext)
    config = Mix.Project.config()
    app = config[:app]
    gettext_config = config[:gettext] || []
    pots = extract(app, gettext_config)
    Application.load(app)

    reports =
      for dir <- backend_dirs(app) do
        GettextReconcile.reconcile(dir, pots,
          dry_run: dry_run?,
          gettext_config: gettext_config,
          blueprint_domains: blueprint_domains(app)
        )
      end

    Mix.shell().info(report(reports, dry_run?))
  end

  # The POT files the extractor composes, `%{path => contents}`, without
  # writing them: `mix gettext.extract` with the writing left to the caller.
  defp extract(app, gettext_config) do
    Gettext.Extractor.enable()
    force_compile()

    for {path, result} <- Gettext.Extractor.pot_files(app, gettext_config), into: %{} do
      case result do
        {:changed, contents} -> {Path.relative_to_cwd(path), IO.iodata_to_binary(contents)}
        :unchanged -> {Path.relative_to_cwd(path), File.read!(path)}
      end
    end
  after
    Gettext.Extractor.disable()
  end

  # As `mix gettext.extract` does: the extractor sees only what compiles.
  defp force_compile do
    if not Version.match?(System.version(), ">= 1.19.3") do
      Mix.Tasks.Compile.Elixir.clean()
      Enum.each(Mix.Tasks.Compile.Elixir.manifests(), &File.rm/1)
    end

    Mix.Task.reenable("compile.elixir")
    Mix.Task.run("compile", ["--force-elixir"])
    Mix.Task.run("compile.elixir", ["--force"])
  end

  # The priv directories of the application's Gettext backends.
  defp backend_dirs(app) do
    {:ok, modules} = :application.get_key(app, :modules)

    modules
    |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, :__gettext__, 1)))
    |> Enum.map(&Path.relative_to_cwd(&1.__gettext__(:priv)))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # `<domain>_<schema>`, the domain each of the application's Blueprints
  # translates its labels in.
  defp blueprint_domains(app) do
    {:ok, modules} = :application.get_key(app, :modules)

    for module <- modules, Code.ensure_loaded?(module), function_exported?(module, :__blueprint__, 0) do
      naming = module.__naming__()
      String.downcase("#{naming.domain}_#{naming.schema}")
    end
  end

  @doc false
  def report(reports, dry_run?) do
    Enum.map_join(reports, "\n", &report_backend(&1, dry_run?))
  end

  defp report_backend(report, dry_run?) do
    {wrote, deleted} = if dry_run?, do: {"Would write", "Would delete"}, else: {"Wrote", "Deleted"}

    files =
      [{wrote, report.written}, {deleted, report.deleted}]
      |> Enum.reject(&(elem(&1, 1) == []))
      |> Enum.map(fn {label, paths} -> "#{label} #{length(paths)}: #{Enum.join(paths, ", ")}" end)

    files = if files == [], do: ["Nothing to change."], else: files
    domains = Enum.map(report.domains, &domain_line/1)
    domains = if domains == [], do: [], else: ["Blueprint domains:" | domains]

    Enum.join(["==> #{report.dir}" | files ++ domains ++ Enum.map(report.warnings, &"! #{&1}")], "\n")
  end

  defp domain_line(domain) do
    counts =
      Enum.join(
        [
          "#{domain.carried} carried",
          "#{length(domain.filled)} filled from a sibling",
          "#{length(domain.dropped)} dropped",
          "#{domain.untranslated} untranslated"
        ],
        ", "
      )

    dropped =
      if domain.dropped == [],
        do: "",
        else: "\n      dropped, no longer in the source: " <> Enum.map_join(domain.dropped, ", ", &inspect/1)

    "  #{domain.domain} (#{domain.locale}): #{counts}#{dropped}"
  end
end

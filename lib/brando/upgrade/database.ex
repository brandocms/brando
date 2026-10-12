defmodule Brando.Upgrade.Database do
  @moduledoc """
  Where an application stands in the database phase of an upgrade, and what
  `mix brando.upgrade.database` runs next.

  `state/2` reads it from the application itself, so there is nothing to keep
  between runs:

    * Brando migration templates without a copy in the migrations directory
      (copies are matched by name, as `mix brando.gen.migrations` does);
    * migrations the database has not run;
    * application Blueprints whose storage differs from their latest snapshot
      (`Brando.Blueprint.Migrations.plan_all/1`, which reads only files);
    * whether the search index was rebuilt after the last migration ran. The
      rebuild is the last derived-data step, so a rebuild older than the last
      migration, or none, means the derived data still needs repairing.

  `plan/2` turns that into the steps of guides/migrating_from_053.md, sections
  3 and 4, each to run, skip (with the reason) or leave for a later run, with
  a stop at the first review point.
  """

  alias Brando.Blueprint.Migrations
  alias Brando.Exception.BlueprintError
  alias Brando.Migration.TemplateDrift

  @type step ::
          :gen_migrations
          | :migrations_check
          | :migrate
          | :legacy_check
          | :gen_blueprint
          | :resave
          | :identifiers
          | :adopt_dry_run
          | :adopt
          | :image_texts
          | :search_index

  @type entry :: {:run, step()} | {:skip, step(), String.t()} | {:later, step(), String.t()} | {:stop, atom()}

  @type state :: %{
          tenancy: Brando.Tenant.mode(),
          database: String.t() | nil,
          missing_templates: [String.t()],
          pending: [{integer(), String.t()}],
          blueprints: {:ok, map()} | {:error, String.t()},
          search: %{rebuilt_at: DateTime.t() | nil, migrated_at: NaiveDateTime.t() | nil}
        }

  @steps [
    :gen_migrations,
    :migrations_check,
    :migrate,
    :legacy_check,
    :gen_blueprint,
    :resave,
    :identifiers,
    :adopt_dry_run,
    :adopt,
    :image_texts,
    :search_index
  ]

  @derived [:resave, :identifiers, :adopt_dry_run, :adopt, :image_texts, :search_index]

  @doc "Every step, in the order they run."
  @spec steps() :: [step()]
  def steps, do: @steps

  @doc "How a step is run by hand: the command a stop message or `--dry-run` names."
  @spec command(step()) :: String.t()
  def command(:gen_migrations), do: "mix brando.gen.migrations"
  def command(:migrations_check), do: "mix brando.migrations.check"
  def command(:migrate), do: "mix brando.migrate"
  def command(:legacy_check), do: "mix brando.check.legacy_conversion"
  def command(:gen_blueprint), do: "mix brando.gen.blueprint_migration --all --reconcile"
  def command(:resave), do: "mix brando.entries.resave --yes"
  def command(:identifiers), do: "mix brando.identifiers.sync"
  def command(:adopt_dry_run), do: "mix brando.images.adopt --dry-run"
  def command(:adopt), do: "mix brando.images.adopt"
  def command(:image_texts), do: "mix brando.check.image_texts"
  def command(:search_index), do: "rebuild the search index (Configuration → Utilities → Search index)"

  @doc """
  Reads the state. `opts`:

    * `:migrations_path` — the application's migrations directory (required)
    * `:templates_path` — Brando's upgrade migration templates
    * `:blueprints` — the application's Blueprints
    * `:snapshot_path` — where their snapshots live
    * `:tenancy` — the configured tenancy mode
    * `:database` — the database's name, for messages

  `repo` must be started.
  """
  @spec state(Ecto.Repo.t(), keyword()) :: state()
  def state(repo, opts) do
    migrations_path = Keyword.fetch!(opts, :migrations_path)

    %{
      tenancy: Keyword.get(opts, :tenancy, :none),
      database: opts[:database],
      missing_templates:
        missing_templates(migrations_path, Keyword.get(opts, :templates_path, TemplateDrift.templates_dir())),
      pending: pending_migrations(repo, migrations_path),
      blueprints:
        blueprints(Keyword.get(opts, :blueprints, []),
          migration_path: migrations_path,
          snapshot_path: Keyword.get(opts, :snapshot_path, "priv/blueprints/snapshots")
        ),
      search: search_index(repo)
    }
  end

  @doc """
  The templates in `templates_path` with no copy in `migrations_path`, by
  file name without the version: what `mix brando.gen.migrations` would copy.
  """
  @spec missing_templates(Path.t(), Path.t()) :: [String.t()]
  def missing_templates(migrations_path, templates_path) do
    copied =
      migrations_path
      |> Path.join("*.exs")
      |> Path.wildcard()
      |> MapSet.new(&strip_version(Path.basename(&1)))

    templates_path
    |> Path.join("brando_*.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.reject(&MapSet.member?(copied, &1))
    |> Enum.sort_by(&template_number/1)
  end

  defp strip_version(name) do
    case Integer.parse(name) do
      {_version, "_" <> rest} -> rest
      _ -> name
    end
  end

  defp template_number(name) do
    case Regex.run(~r/^brando_(\d+)_/, name) do
      [_, number] -> String.to_integer(number)
      nil -> 0
    end
  end

  @doc "The migrations in `migrations_path` that `repo` has not run, as `{version, name}`."
  @spec pending_migrations(Ecto.Repo.t(), Path.t()) :: [{integer(), String.t()}]
  def pending_migrations(repo, migrations_path) do
    for {:down, version, name} <- Ecto.Migrator.migrations(repo, [migrations_path]), do: {version, name}
  end

  @doc """
  Plans every Blueprint in `modules` against its latest snapshot, without
  writing anything or reading the database. Returns the Blueprints whose
  storage differs (`:changed`), those up to date, and those left out because
  they fix their own schema prefix, which `--all` leaves out too.
  """
  @spec blueprints([module()], keyword()) :: {:ok, map()} | {:error, String.t()}
  def blueprints(modules, opts) do
    {public, left_out} =
      modules
      |> Enum.uniq()
      |> Enum.reject(&Brando.Blueprint.embedded?/1)
      |> Enum.sort_by(&inspect/1)
      |> Enum.split_with(&(&1.__schema__(:prefix) in [nil, "public"]))

    {up_to_date, changed} =
      public
      |> Enum.map(&{&1, opts})
      |> Migrations.plan_all()
      |> Enum.split_with(&match?(%{result: :noop, snapshot: nil}, &1))

    {:ok, %{changed: Enum.map(changed, & &1.module), up_to_date: Enum.map(up_to_date, & &1.module), left_out: left_out}}
  rescue
    error in [BlueprintError, File.Error] -> {:error, Exception.message(error)}
  end

  @doc """
  When the search index was last rebuilt in full, and when the last migration
  ran (`schema_migrations.inserted_at`, UTC).
  """
  @spec search_index(Ecto.Repo.t()) :: %{rebuilt_at: DateTime.t() | nil, migrated_at: NaiveDateTime.t() | nil}
  def search_index(repo) do
    source = repo.config()[:migration_source] || "schema_migrations"
    %{rows: [[migrated_at]]} = repo.query!("SELECT max(inserted_at) FROM #{source}", [], log: false)
    %{rebuilt_at: Brando.Search.rebuilt_at(), migrated_at: migrated_at}
  end

  @doc """
  The steps for `state`, in order: `{:run, step}`, `{:skip, step, why}`, a
  `{:stop, reason}` at the first review point, and `{:later, step, why}` for
  the steps after it. A plan without a stop ends in `{:stop, :done}`.

  `opts`: `skip_conversion_check: true` skips `mix brando.check.legacy_conversion`.

  Steps that write source files stop the run after them, so the files are
  reviewed and committed before anything uses them. Database steps follow
  the review of what they apply; the task asks before each.
  """
  @spec plan(state(), keyword()) :: [entry()]
  def plan(state, opts \\ [])

  def plan(%{tenancy: mode}, _opts) when mode in [:single, :multi], do: [{:stop, :tenancy}]

  def plan(%{missing_templates: [_ | _]}, _opts) do
    [{:run, :gen_migrations}, {:stop, :review_migrations} | later(@steps -- [:gen_migrations])]
  end

  def plan(state, opts) do
    brando_pending? = Enum.any?(state.pending, &brando_migration?/1)

    [{:skip, :gen_migrations, "every Brando migration template has a copy"}]
    |> Kernel.++(migrate_steps(state, brando_pending?))
    |> Kernel.++(blueprint_steps(state, brando_pending?, opts))
    |> then(fn entries ->
      if Enum.any?(entries, &match?({:stop, _}, &1)),
        do: entries ++ later(@derived),
        else: entries ++ derived_steps(state)
    end)
  end

  defp migrate_steps(state, brando_pending?) do
    check =
      if brando_pending?,
        do: {:run, :migrations_check},
        else: {:skip, :migrations_check, "no Brando migration is pending"}

    migrate =
      if state.pending == [],
        do: {:skip, :migrate, "every migration has run"},
        else: {:run, :migrate}

    [check, migrate]
  end

  defp blueprint_steps(%{blueprints: {:error, _message}}, brando_pending?, opts) do
    [
      legacy_check(brando_pending?, true, opts),
      {:stop, :blueprint_error},
      {:later, :gen_blueprint, "waits until the Blueprints can be planned"}
    ]
  end

  defp blueprint_steps(%{blueprints: {:ok, %{changed: changed}}}, brando_pending?, opts) do
    if changed == [] do
      [
        legacy_check(brando_pending?, false, opts),
        {:skip, :gen_blueprint, "every Blueprint matches its latest snapshot"}
      ]
    else
      [legacy_check(brando_pending?, true, opts), {:run, :gen_blueprint}, {:stop, :review_blueprint_migrations}]
    end
  end

  # The conversion check reads the Villain columns the Blueprint migrations
  # could drop, so it runs before they are generated, and again on every run
  # until they are: a failed check is not forgotten by rerunning.
  defp legacy_check(brando_pending?, blueprints_pending?, opts) do
    cond do
      not (brando_pending? or blueprints_pending?) ->
        {:skip, :legacy_check, "no Brando migration is pending and no Blueprint migration is due"}

      opts[:skip_conversion_check] ->
        {:skip, :legacy_check, "--skip-conversion-check"}

      true ->
        {:run, :legacy_check}
    end
  end

  defp derived_steps(state) do
    case derived_reason(state) do
      nil ->
        why = "the search index was rebuilt after the last migration, so the derived data counts as repaired"
        Enum.map(@derived, &{:skip, &1, why}) ++ [{:stop, :done}]

      _reason ->
        Enum.map(@derived, &{:run, &1}) ++ [{:stop, :done}]
    end
  end

  @doc "Why the derived data needs repairing, or nil when it looks repaired."
  @spec derived_reason(state()) :: String.t() | nil
  def derived_reason(%{pending: [_ | _]}), do: "migrations are pending"
  def derived_reason(%{search: %{rebuilt_at: nil}}), do: "the search index has never been rebuilt"
  def derived_reason(%{search: %{migrated_at: nil}}), do: nil

  def derived_reason(%{search: %{rebuilt_at: rebuilt_at, migrated_at: migrated_at}}) do
    if NaiveDateTime.compare(DateTime.to_naive(rebuilt_at), migrated_at) == :lt,
      do: "migrations ran after the search index was last rebuilt",
      else: nil
  end

  defp later(steps), do: Enum.map(steps, &{:later, &1, "waits for the review"})

  @doc "Whether a pending `{version, name}` is one of Brando's own migrations."
  @spec brando_migration?({integer(), String.t()}) :: boolean()
  def brando_migration?({_version, name}), do: String.starts_with?(name, "brando_")
end

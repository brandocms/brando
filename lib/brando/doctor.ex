defmodule Brando.Doctor do
  @moduledoc """
  Checks that explain what is misconfigured or out of date in a Brando
  application: pending migrations, admin assets from an older publish, images
  made with older settings, blocks on outdated module versions, a missing
  sitemap and so on.

  `mix brando.doctor` prints the results, and Utilities in the admin shows
  them as the "System check" card. Checks only read; a result names the fix
  and, where there is one, links to the admin screen for it.

  Each check is a module implementing `Brando.Doctor.Check`. Brando's own
  run first, then the application's:

      config :brando, Brando.Doctor,
        checks: [MyApp.Doctor.SearchIndex],
        skip: [Brando.Doctor.Checks.AltText]

  See the [System check guide](doctor.md).
  """

  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Checks
  alias Brando.Doctor.Context
  alias Brando.Doctor.Result

  @default_checks [
    Checks.Versions,
    Checks.Migrations,
    Checks.Oban,
    Checks.Configuration,
    Checks.AdminAssets,
    Checks.ImageConfigs,
    Checks.Modules,
    Checks.Sitemap,
    Checks.Robots,
    Checks.JSONLD,
    Checks.AltText,
    Checks.Deprecations
  ]

  @timeout :timer.seconds(60)

  @doc "Brando's own checks, in the order they are shown."
  @spec default_checks() :: [module()]
  def default_checks, do: @default_checks

  @doc """
  The checks to run: Brando's, then the application's `:checks`, without the
  ones listed in `:skip`.
  """
  @spec checks() :: [module()]
  def checks do
    config = Application.get_env(:brando, __MODULE__, [])
    skip = Keyword.get(config, :skip, [])

    (@default_checks ++ Keyword.get(config, :checks, []))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in skip))
  end

  @doc """
  Runs `checks` (default: `checks/0`) and returns their results in order.

  `:sandbox` is a LiveView's SQL sandbox metadata, for the admin's checks in
  a test. The rest of `opts` builds the `Brando.Doctor.Context`. A check that raises
  or takes longer than a minute is reported as an error rather than stopping
  the others.
  """
  @spec run(keyword()) :: [Result.t()]
  def run(opts \\ []) do
    {checks, opts} = Keyword.pop_lazy(opts, :checks, &checks/0)
    {sandbox, opts} = Keyword.pop(opts, :sandbox)
    context = Context.new(opts)

    checks
    |> Task.async_stream(
      fn check ->
        allow_sandbox(sandbox)
        run_check(check, context)
      end,
      ordered: true,
      timeout: @timeout,
      on_timeout: :kill_task,
      max_concurrency: min(System.schedulers_online(), 4)
    )
    |> Enum.zip(checks)
    |> Enum.map(fn
      {{:ok, result}, _check} -> result
      {{:exit, :timeout}, check} -> failed(check, context, dgettext("doctor", "took too long"))
      {{:exit, reason}, check} -> failed(check, context, Exception.format_exit(reason))
    end)
  end

  @doc "Runs one check in `context`, as `run/1` does."
  @spec run_check(module(), Context.t()) :: Result.t()
  def run_check(check, %Context{} = context) do
    Gettext.put_locale(Brando.Gettext, context.locale)
    Gettext.put_locale(context.locale)

    with_prefix(context.prefix, fn ->
      result =
        try do
          cond do
            not implements?(check) ->
              Result.error(dgettext("doctor", "not a Brando.Doctor.Check"))

            needs_source?(check) and not context.source? ->
              Result.skipped(dgettext("doctor", "skipped in a release: needs the project's source files"))

            true ->
              check.run(context)
          end
        rescue
          exception -> Result.error(dgettext("doctor", "could not run"), items: [Exception.message(exception)])
        end

      %{result | check: check, id: id(check), label: label(check)}
    end)
  end

  @doc "Counts results by status: `%{ok: 7, warning: 3, error: 1, skipped: 0}`."
  @spec counts([Result.t()]) :: %{Result.status() => non_neg_integer()}
  def counts(results) do
    Map.merge(Map.new(Result.statuses(), &{&1, 0}), Enum.frequencies_by(results, & &1.status))
  end

  @doc """
  The overall status: `:error` when any check failed, else `:warning` when any
  warned, else `:ok`.
  """
  @spec status([Result.t()]) :: :ok | :warning | :error
  def status(results) do
    results
    |> Enum.map(& &1.status)
    |> Enum.reduce(:ok, &Result.worst/2)
    |> case do
      :skipped -> :ok
      status -> status
    end
  end

  @doc """
  The exit status for `results`: 1 with an error, or with a warning when
  `strict?`; 0 otherwise.
  """
  @spec exit_status([Result.t()], boolean()) :: 0 | 1
  def exit_status(results, strict? \\ false) do
    case status(results) do
      :error -> 1
      :warning when strict? -> 1
      _ -> 0
    end
  end

  @doc "The versions the doctor reports in its header."
  @spec versions() :: %{atom() => String.t() | nil}
  def versions do
    %{
      brando: Brando.version(),
      elixir: System.version(),
      otp: System.otp_release(),
      phoenix: app_version(:phoenix),
      live_view: app_version(:phoenix_live_view)
    }
  end

  @doc false
  def app_version(app) do
    case Application.spec(app, :vsn) do
      nil -> nil
      vsn -> to_string(vsn)
    end
  end

  defp failed(check, context, reason) do
    Gettext.put_locale(Brando.Gettext, context.locale)

    %{
      Result.error(dgettext("doctor", "could not run"), items: [reason])
      | check: check,
        id: id(check),
        label: label(check)
    }
  end

  defp implements?(check) do
    Code.ensure_loaded?(check) and function_exported?(check, :run, 1) and function_exported?(check, :label, 0)
  end

  defp needs_source?(check), do: function_exported?(check, :needs_source?, 0) and check.needs_source?()

  defp id(check) do
    if function_exported?(check, :id, 0),
      do: check.id(),
      else: check |> Module.split() |> List.last() |> Macro.underscore()
  rescue
    _ -> inspect(check)
  end

  defp label(check) do
    if Code.ensure_loaded?(check) and function_exported?(check, :label, 0), do: check.label(), else: inspect(check)
  rescue
    _ -> inspect(check)
  end

  # In a test, the admin's checks read the test's SQL sandbox. Its
  # connections are not inherited by tasks in the sandbox's `:auto` mode, so
  # each check's task joins it (`:sandbox`, the LiveView's sandbox metadata).
  defp allow_sandbox(nil), do: :ok
  defp allow_sandbox(sandbox), do: Phoenix.Ecto.SQL.Sandbox.allow(sandbox, Ecto.Adapters.SQL.Sandbox)

  defp with_prefix(nil, fun), do: fun.()
  defp with_prefix(prefix, fun), do: Brando.Tenant.with_prefix(prefix, fun)
end

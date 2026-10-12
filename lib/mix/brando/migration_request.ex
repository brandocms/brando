defmodule Mix.Brando.MigrationRequest do
  @moduledoc false

  alias Brando.Blueprint.Migrations
  alias Brando.Exception.BlueprintError

  def encode(plan) do
    version =
      if plan.metadata[:migration],
        do: plan.metadata.migration |> Path.basename() |> String.split("_", parts: 2) |> hd() |> String.to_integer()

    %{
      "module" => inspect(plan.module),
      "digest" => Migrations.plan_digest(plan),
      "migration_path" => plan.options[:migration_path],
      "snapshot_path" => plan.options[:snapshot_path],
      "rebaseline" => plan.options[:rebaseline] || false,
      "reconcile" => plan.options[:reconcile] || false,
      "version" => version
    }
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  # Igniter lists a queued task with its arguments ("These tasks will be
  # run") and runs it as a `mix` command of its own, and an encoded request is
  # a long base64 string. Each request is kept in a file under the build path,
  # named after its Blueprint, and the task's arguments are the Blueprints'
  # names. An argument that names no kept request is taken as an encoded
  # request; the digest inside still refuses a plan that changed since.
  def task_args(plans) do
    Enum.map(plans, fn plan ->
      name = inspect(plan.module)
      file = kept_file(name)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, encode(plan))
      name
    end)
  end

  def apply(argument) do
    result = argument |> kept() |> reviewed_plan() |> Migrations.commit_plan()
    forget([argument])
    result
  end

  # Every request is checked against its review before any of them is written.
  def apply_all(arguments) do
    result = arguments |> Enum.map(&(&1 |> kept() |> reviewed_plan())) |> Migrations.commit_plans()
    forget(arguments)
    result
  end

  defp kept(argument) do
    case kept_file(argument) do
      nil -> argument
      file -> if File.regular?(file), do: File.read!(file), else: argument
    end
  end

  defp forget(arguments) do
    for argument <- arguments, file = kept_file(argument), do: File.rm(file)
  end

  defp kept_file(name) do
    if Regex.match?(~r/\A[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*\z/, name),
      do: Path.join([Mix.Project.build_path(), "brando", "blueprint_plans", name])
  end

  # A reconciled plan reads the database. A Mix task does not start the repo,
  # and its URL usually lives in config/runtime.exs, so load the configuration
  # and start the repo as Ecto's own tasks do.
  def with_database(false, fun), do: fun.()

  def with_database(true, fun) do
    Mix.Task.run("app.config")
    repo = Brando.repo()

    unless is_atom(repo) and not is_nil(repo) and Code.ensure_loaded?(repo) do
      raise BlueprintError,
        message: "--reconcile reads the database, but no repo is configured. Set config :brando, repo: MyApp.Repo."
    end

    case Ecto.Migrator.with_repo(repo, fn _repo -> fun.() end) do
      {:ok, result, _apps} ->
        result

      {:error, reason} ->
        raise BlueprintError,
          message: "--reconcile reads the database, but #{inspect(repo)} did not start: #{inspect(reason)}"
    end
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      reraise BlueprintError,
              [message: "--reconcile reads the database, which failed: #{Exception.message(error)}"],
              __STACKTRACE__
  end

  defp reviewed_plan(request) do
    with {:ok, json} <- Base.url_decode64(request, padding: false),
         {:ok, values} <- Jason.decode(json),
         true <- valid?(values) do
      reconcile = Map.get(values, "reconcile", false)

      options = [
        migration_path: values["migration_path"],
        snapshot_path: values["snapshot_path"],
        rebaseline: values["rebaseline"],
        reconcile: reconcile
      ]

      options =
        if values["version"], do: Keyword.put(options, :planned_migration_version, values["version"]), else: options

      plan = with_database(reconcile, fn -> Migrations.plan(Module.concat([values["module"]]), options) end)

      unless Migrations.plan_digest(plan) == values["digest"],
        do:
          Mix.raise(
            "The reviewed Blueprint migration plan is stale. Generate and review it again; no files were written."
          )

      plan
    else
      _ -> Mix.raise("Invalid Blueprint migration request. Run mix brando.gen.blueprint_migration to prepare a new plan.")
    end
  end

  defp valid?(
         %{
           "module" => module,
           "digest" => digest,
           "migration_path" => migration_path,
           "snapshot_path" => snapshot_path,
           "rebaseline" => rebaseline,
           "version" => version
         } = values
       ) do
    is_binary(module) && Regex.match?(~r/^[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*$/, module) &&
      is_binary(digest) && Regex.match?(~r/^[0-9a-f]{64}$/, digest) &&
      is_binary(migration_path) && is_binary(snapshot_path) && is_boolean(rebaseline) &&
      is_boolean(Map.get(values, "reconcile", false)) && valid_version?(version)
  end

  defp valid?(_), do: false
  defp valid_version?(nil), do: true
  defp valid_version?(version), do: is_integer(version) && version > 0
end

defmodule Mix.Brando.MigrationRequest do
  @moduledoc false

  alias Brando.Blueprint.Migrations

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
      "version" => version
    }
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  def apply(request) do
    with {:ok, json} <- Base.url_decode64(request, padding: false),
         {:ok, values} <- Jason.decode(json),
         true <- valid?(values) do
      options = [
        migration_path: values["migration_path"],
        snapshot_path: values["snapshot_path"],
        rebaseline: values["rebaseline"]
      ]

      options =
        if values["version"], do: Keyword.put(options, :planned_migration_version, values["version"]), else: options

      plan = Migrations.plan(Module.concat([values["module"]]), options)

      unless Migrations.plan_digest(plan) == values["digest"],
        do:
          Mix.raise(
            "The reviewed Blueprint migration plan is stale. Generate and review it again; no files were written."
          )

      Migrations.commit_plan(plan)
    else
      _ -> Mix.raise("Invalid Blueprint migration request. Run mix brando.gen.blueprint_migration to prepare a new plan.")
    end
  end

  defp valid?(%{
         "module" => module,
         "digest" => digest,
         "migration_path" => migration_path,
         "snapshot_path" => snapshot_path,
         "rebaseline" => rebaseline,
         "version" => version
       }) do
    is_binary(module) && Regex.match?(~r/^[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*$/, module) &&
      is_binary(digest) && Regex.match?(~r/^[0-9a-f]{64}$/, digest) &&
      is_binary(migration_path) && is_binary(snapshot_path) && is_boolean(rebaseline) &&
      valid_version?(version)
  end

  defp valid?(_), do: false
  defp valid_version?(nil), do: true
  defp valid_version?(version), do: is_integer(version) && version > 0
end

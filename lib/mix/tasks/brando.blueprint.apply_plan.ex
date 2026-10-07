defmodule Mix.Tasks.Brando.Blueprint.ApplyPlan do
  use Mix.Task
  @moduledoc false
  @requirements ["app.config"]

  @impl Mix.Task
  def run([request]), do: request |> Mix.Brando.MigrationRequest.apply() |> report()

  # brando.gen.blueprint_migration --all queues one request per Blueprint; they
  # are written together or not at all.
  def run([_, _ | _] = requests) do
    requests
    |> Mix.Brando.MigrationRequest.apply_all()
    |> Enum.each(&report/1)
  end

  def run(_), do: Mix.raise("This internal task requires a reviewed Blueprint migration request.")

  defp report({:ok, %{migration: migration, snapshot: snapshot}}) do
    Mix.shell().info("Created #{migration}")
    Mix.shell().info("Created #{snapshot}")
  end

  defp report({:ok, %{snapshot: snapshot}}), do: Mix.shell().info("Re-baselined at #{snapshot}")

  defp report({:noop, metadata}),
    do: Mix.shell().info("No storage changes necessary for #{inspect(metadata.module)}.")
end

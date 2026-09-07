defmodule Mix.Tasks.Brando.Blueprint.ApplyPlan do
  use Mix.Task
  @moduledoc false
  @requirements ["app.config"]

  @impl Mix.Task
  def run([request]) do
    case Mix.Brando.MigrationRequest.apply(request) do
      {:ok, %{migration: migration, snapshot: snapshot}} ->
        Mix.shell().info("Created #{migration}")
        Mix.shell().info("Created #{snapshot}")

      {:ok, %{snapshot: snapshot}} ->
        Mix.shell().info("Re-baselined at #{snapshot}")

      {:noop, metadata} ->
        Mix.shell().info("No storage changes necessary for #{inspect(metadata.module)}.")
    end
  end

  def run(_), do: Mix.raise("This internal task requires a reviewed Blueprint migration request.")
end

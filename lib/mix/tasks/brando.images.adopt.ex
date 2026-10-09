defmodule Mix.Tasks.Brando.Images.Adopt do
  @shortdoc "Records the settings of images made before Brando recorded them"

  @moduledoc """
  Records the current config of the images processed before Brando recorded
  image configs (0.55), where their files already match it, so they aren't
  recreated:

      mix brando.images.adopt
      mix brando.images.adopt --dry-run
      mix brando.images.adopt --verbose

  Run it once after upgrading from 0.54. It goes through every environment of
  every active site when tenancy is on. Each image's formats, size keys, files
  and the files' pixel dimensions are checked against its config, reading only
  the files' headers; a match gets the config's fingerprint and nothing else
  changes. Quality and other encoder settings can't be read from a file and
  are not compared. See `Brando.Images.Adoption`.

  The images that differ keep no fingerprint: recreate them with Utilities →
  Recreate changed images, which recreates only those. Running the task again
  does nothing more for images already adopted.

    * `--dry-run` counts without writing anything.
    * `--verbose` lists the images that differ and why.

  The application starts without its web server and with Oban's queues
  stopped.
  """

  use Mix.Task

  alias Brando.Doctor.Context
  alias Brando.Tenant

  @switches [dry_run: :boolean, verbose: :boolean]
  @aliases [n: :dry_run, v: :verbose]

  @impl Mix.Task
  def run(args) do
    {opts, _positional} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    Mix.Brando.start_quietly()

    dry_run? = opts[:dry_run] == true
    results = adopt(Context.new(mode: :mix).environments, dry_run: dry_run?, verbose: opts[:verbose] == true)

    totals =
      Enum.reduce(results, %{adopted: 0, differ: 0, skipped: 0}, &Map.merge(&2, elem(&1, 1), fn _k, a, b -> a + b end))

    cond do
      totals.differ > 0 ->
        Mix.shell().info(
          "\nRecreate the #{totals.differ} that differ with Utilities → Recreate changed images. It recreates only those."
        )

      dry_run? and totals.adopted > 0 ->
        Mix.shell().info("\nRun without --dry-run to record them.")

      true ->
        :ok
    end
  end

  @doc false
  # Adopts in each `{label, prefix}` environment and prints a line for each.
  # Returns `[{label, counts}]`.
  def adopt(environments, opts) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    on_differ = if Keyword.get(opts, :verbose, false), do: &print_differ/2

    Enum.map(environments, fn {label, prefix} ->
      counts =
        Tenant.with_prefix(prefix, fn ->
          Brando.Images.Processing.adopt_unrecorded(dry_run: dry_run?, on_differ: on_differ)
        end)

      Mix.shell().info(line(label, counts, dry_run?))
      {label, counts}
    end)
  end

  defp line(label, %{adopted: adopted, differ: differ, skipped: skipped}, dry_run?) do
    adopted = if dry_run?, do: "#{adopted} already match", else: "#{adopted} adopted"
    text = "#{adopted}, #{differ} differ, #{skipped} skipped"
    if label, do: "[#{label}] #{text}", else: text
  end

  defp print_differ(image, verdict) do
    Mix.shell().info("  image #{image.id} (#{image.config_target}): #{reason(verdict)}")
  end

  defp reason({:differ, :formats}), do: "its formats differ"
  defp reason({:differ, :size_keys}), do: "its sizes differ"
  defp reason({:differ, {:missing, key}}), do: "#{key} is missing"
  defp reason({:differ, {:dimensions, key}}), do: "#{key} has other dimensions"
  defp reason({:differ, {:error, message}}), do: "could not be checked: #{message}"
  defp reason({:skipped, :cdn}), do: "on the CDN without a local copy, not checked"
  defp reason({:skipped, :no_config}), do: "its config target no longer resolves"
  defp reason(other), do: inspect(other)
end

defmodule Mix.Tasks.Brando.Videos.MuxRenditions do
  use Mix.Task

  @shortdoc "Lists (or asks Mux for) the static renditions existing Mux videos lack"

  @moduledoc """
  Shows which ready Mux videos lack the static renditions in
  `config :brando, Brando.Videos, mux_static_renditions: [720, 1080]`, in
  every environment of every active site, and with `--apply` asks Mux to make
  them. A video plays an MP4 once Mux reports its rendition ready, through the
  `video.asset.static_rendition.ready` webhook; until then it streams. Running
  the task again stores what is ready by then and asks for nothing twice.

      mix brando.videos.mux_renditions          # list, change nothing
      mix brando.videos.mux_renditions --apply  # ask Mux for them

  Each rendition has its own storage and delivery cost on Mux. In a release,
  `Brando.Videos.Uploaders.Mux.add_static_renditions/1` does the same.
  """

  alias Brando.Videos.Uploaders.Mux

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [apply: :boolean])
    apply? = Keyword.get(opts, :apply, false)

    Mix.Brando.start_quietly()

    unless Mux.configured?() do
      Mix.raise("Mux credentials are not configured (config :brando, Brando.Videos.Uploaders.Mux)")
    end

    results = Mux.add_static_renditions(dry_run: not apply?)

    report(results, Mux.static_rendition_resolutions(), apply?)
  end

  @doc false
  def report(_results, [], _apply?),
    do: Mix.shell().info("No static renditions configured (mux_static_renditions: []).")

  def report(results, resolutions, apply?) do
    Mix.shell().info("Static renditions: #{format(resolutions)}\n")

    lacking = Enum.filter(results, &(&1.requested != [] or &1.failed != [] or &1.error))

    for result <- lacking do
      Mix.shell().info("#{result.environment}  ##{result.video_id} #{inspect(result.title)}  #{outcome(result, apply?)}")
    end

    Mix.shell().info(
      "\n#{length(results)} Mux videos, #{length(results) - length(lacking)} with every rendition." <>
        if(apply? or lacking == [], do: "", else: " Nothing changed; run with --apply to ask Mux for them.")
    )
  end

  defp outcome(%{error: error}, _apply?) when not is_nil(error), do: "FAILED to read the asset: #{inspect(error)}"

  defp outcome(result, apply?) do
    asked = if result.requested == [], do: [], else: [verb(apply?) <> " " <> format(result.requested)]
    failed = Enum.map(result.failed, fn {resolution, reason} -> "FAILED #{resolution}p: #{inspect(reason)}" end)
    Enum.join(asked ++ failed, "  ")
  end

  defp verb(true), do: "asked for"
  defp verb(false), do: "would ask for"

  defp format(resolutions), do: Enum.map_join(resolutions, ", ", &"#{&1}p")
end

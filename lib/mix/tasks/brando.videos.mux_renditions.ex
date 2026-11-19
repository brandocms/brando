defmodule Mix.Tasks.Brando.Videos.MuxRenditions do
  use Mix.Task

  @shortdoc "Lists (or asks Mux for) the static renditions existing Mux videos lack"

  @moduledoc """
  Shows which ready Mux videos would play an MP4 and lack the static
  renditions in `config :brando, Brando.Videos, mux_static_renditions: [720, 1080]`,
  in every environment of every active site, and with `--apply` asks Mux to
  make them. A video would play an MP4 when it is shown somewhere as an
  autoplaying loop without controls or a play button under Automatic quality,
  or has a fixed MP4 quality on the video or a placement; videos that only
  stream are skipped.

  Mux won't make a resolution beside an older asset's `highest` rendition or
  while its legacy `mp4_support` is on, so `--apply` first deletes `highest`
  or turns `mp4_support` off on such an asset. The list says which.

  A video plays an MP4 once Mux reports its rendition ready, through the
  `video.asset.static_rendition.ready` webhook; until then it streams.
  Running the task again stores what is ready by then, asks for nothing
  twice, and picks up videos that became loops since.

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
    Mix.shell().info("Static renditions: #{Enum.map_join(resolutions, ", ", &"#{&1}p")}\n")

    {skipped, playing} = Enum.split_with(results, &(&1.skipped == :streams))
    lacking = Enum.filter(playing, &(&1.requested != [] or &1.failed != [] or &1.error))

    for result <- lacking ++ skipped do
      Mix.shell().info(
        "#{result.environment}  ##{result.video_id} #{inspect(result.title)}  #{Mux.describe_result(result, apply?)}"
      )
    end

    Mix.shell().info(
      "\n#{length(results)} Mux videos: #{length(playing) - length(lacking)} with every rendition, " <>
        "#{length(skipped)} only streaming." <>
        if(apply? or lacking == [], do: "", else: " Nothing changed; run with --apply to ask Mux for them.")
    )
  end
end

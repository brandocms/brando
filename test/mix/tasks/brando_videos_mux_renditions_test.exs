defmodule Mix.Tasks.Brando.Videos.MuxRenditionsTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Brando.Videos.MuxRenditions

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp result(attrs),
    do:
      Map.merge(
        %{environment: "public", video_id: 1, title: "Loop", present: [], requested: [], failed: [], error: nil},
        attrs
      )

  defp lines do
    Stream.repeatedly(fn ->
      receive do
        {:mix_shell, :info, [line]} -> line
      after
        0 -> nil
      end
    end)
    |> Enum.take_while(& &1)
    |> Enum.join("\n")
  end

  test "lists the videos lacking renditions, and what applying would ask for" do
    MuxRenditions.report(
      [
        result(%{video_id: 1, requested: [1080], present: [720]}),
        result(%{video_id: 2, title: "Done", present: [720, 1080]}),
        result(%{video_id: 3, title: "Gone", error: :not_found})
      ],
      [720, 1080],
      false
    )

    output = lines()
    assert output =~ "Static renditions: 720p, 1080p"
    assert output =~ ~s(#1 "Loop"  would ask for 1080p)
    refute output =~ "#2"
    assert output =~ ~s(#3 "Gone"  FAILED to read the asset: :not_found)
    assert output =~ "3 Mux videos, 1 with every rendition. Nothing changed; run with --apply"
  end

  test "applying reports what was asked for and what Mux refused" do
    MuxRenditions.report([result(%{requested: [1080], failed: [{720, %{"error" => "no"}}]})], [720, 1080], true)

    output = lines()
    assert output =~ ~s(asked for 1080p  FAILED 720p: %{"error" => "no"})
    refute output =~ "--apply"
  end

  test "says so when no renditions are configured" do
    MuxRenditions.report([], [], true)
    assert lines() =~ "No static renditions configured"
  end
end

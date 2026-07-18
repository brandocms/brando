defmodule Brando.Videos.Uploaders.BunnyTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Videos.Uploaders.Bunny

  setup do
    previous = Application.get_env(:brando, Bunny)
    Application.put_env(:brando, Bunny, library_id: "133")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:brando, Bunny, previous),
        else: Application.delete_env(:brando, Bunny)
    end)
  end

  test "late processing webhooks cannot regress a ready video" do
    user = Factory.insert(:user)
    guid = Ecto.UUID.generate()

    video =
      Factory.insert(:video,
        creator: user,
        type: :bunny,
        status: :ready,
        meta: %{"provider" => "bunny", "bunny" => %{"video_guid" => guid}}
      )

    assert {:ok, updated_video} =
             Bunny.handle_webhook(%{"VideoLibraryId" => 133, "VideoGuid" => guid, "Status" => 2})

    assert updated_video.id == video.id
    assert updated_video.status == :ready
    assert Brando.Repo.reload!(video).status == :ready
  end

  test "terminal errors ignore later stale provider status" do
    user = Factory.insert(:user)
    guid = Ecto.UUID.generate()

    video =
      Factory.insert(:video,
        creator: user,
        type: :bunny,
        status: :errored,
        meta: %{"provider" => "bunny", "bunny" => %{"video_guid" => guid}}
      )

    assert {:ok, updated_video} =
             Bunny.handle_webhook(%{"VideoLibraryId" => 133, "VideoGuid" => guid, "Status" => 3})

    assert updated_video.status == :errored
    assert Brando.Repo.reload!(video).status == :errored
  end
end

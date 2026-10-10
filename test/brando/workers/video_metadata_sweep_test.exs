defmodule Brando.Worker.VideoMetadataSweepTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Worker.VideoMetadata
  alias Brando.Worker.VideoMetadataSweep

  test "queues a lookup for each video missing its details" do
    user = Factory.insert(:random_user)
    missing = Factory.insert(:video, creator: user, title: nil)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = perform_job(VideoMetadataSweep, %{"user_id" => user.id})
      assert [%{args: %{"video_id" => video_id, "user_id" => user_id}}] = all_enqueued(worker: VideoMetadata)
      assert {video_id, user_id} == {missing.id, user.id}
    end)
  end

  test "a sweep asked for while one waits joins it" do
    user = Factory.insert(:random_user)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, %{conflict?: false}} = VideoMetadataSweep.enqueue(user)
      assert {:ok, %{conflict?: true}} = VideoMetadataSweep.enqueue(user.id)
      assert [_one] = all_enqueued(worker: VideoMetadataSweep)
    end)
  end
end

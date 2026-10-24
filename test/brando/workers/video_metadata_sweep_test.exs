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

  # Someone else's waiting sweep reports to them, not to whoever asked second
  test "a second user's work ends at once when another user's sweep waits" do
    first = Factory.insert(:random_user)
    second = Factory.insert(:random_user)
    BrandoAdmin.Work.subscribe(first)
    BrandoAdmin.Work.subscribe(second)
    key = VideoMetadataSweep.work_key()

    Oban.Testing.with_testing_mode(:manual, fn ->
      BrandoAdmin.Work.start(first, key, "Looking up")
      assert {:ok, %{conflict?: false}} = VideoMetadataSweep.enqueue(first)
      BrandoAdmin.Work.start(second, key, "Looking up")
      assert {:ok, %{conflict?: true}} = VideoMetadataSweep.enqueue(second)
    end)

    second_id = second.id

    assert_receive {:work, ^key, :finished,
                    %BrandoAdmin.Work{user_id: ^second_id, message: "The videos are already being looked up"}}

    assert %BrandoAdmin.Work{status: :running} = BrandoAdmin.Work.get(first, key)
    BrandoAdmin.Work.finish(first, key)
  end

  test "a sweep that fails ends its work" do
    user = Factory.insert(:random_user)
    BrandoAdmin.Work.subscribe(user)
    key = VideoMetadataSweep.work_key()
    BrandoAdmin.Work.start(user, key, "Looking up")

    # With sites, a sweep queued without one cancels
    put_test_env(:tenancy_mode, :multi)

    {:ok, _job} =
      %{"user_id" => user.id}
      |> VideoMetadataSweep.new()
      |> BrandoAdmin.Work.track(user, key, finish: false, failed: "Could not look the videos up")
      |> Oban.insert()

    assert_receive {:work, ^key, :failed, %BrandoAdmin.Work{message: "Could not look the videos up"}}
  end
end

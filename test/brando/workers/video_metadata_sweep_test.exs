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

  # Oban takes the lock only outside testing modes: the conflict it returns
  # then has no id, and the caller's own args
  test "an insert that lost the race for the lock ends its work" do
    user = Factory.insert(:random_user)
    BrandoAdmin.Work.subscribe(user)
    key = VideoMetadataSweep.work_key()
    BrandoAdmin.Work.start(user, key, "Looking up")

    VideoMetadataSweep.end_joined({:ok, %Oban.Job{conflict?: true, id: nil, args: %{"user_id" => user.id}}}, user.id)
    assert_receive {:work, ^key, :finished, %BrandoAdmin.Work{message: "The videos are already being looked up"}}

    # The user's own waiting sweep keeps it
    BrandoAdmin.Work.start(user, key, "Looking up")
    VideoMetadataSweep.end_joined({:ok, %Oban.Job{conflict?: true, id: 1, args: %{"user_id" => user.id}}}, user.id)
    refute_receive {:work, ^key, :finished, _}, 100
    BrandoAdmin.Work.finish(user, key)
  end

  # The sweep hands its work on to the lookups, and ends it only if it fails
  # (BrandoAdmin.WorkTest covers `finish: false`)
  test "a sweep reports only its failure, in the language of whoever asked" do
    user = Factory.insert(:random_user)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _job} = VideoMetadataSweep.enqueue(user)

      assert [%{meta: %{"brando_work" => work}}] = all_enqueued(worker: VideoMetadataSweep)
      user_id = user.id

      assert %{
               "user_id" => ^user_id,
               "key" => "video-metadata",
               "finish" => false,
               "failed" => "Could not look the videos up"
             } =
               work
    end)
  end
end

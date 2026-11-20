defmodule Brando.Content.Proposals.ImageReplacementSizeRunTest do
  # A replacement approved while a run of Image sizes (`Brando.Images.SizeRun`)
  # waits to recreate NEW: NEW's job goes with its record, and the run still
  # ends as done. Synchronous: a run is read from every image job.
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.ReplaceImageFile
  alias Brando.Images.{Image, Processing, SizeRun}
  alias BrandoAdmin.Work

  setup do
    Brando.ProposalFixtures.context()
  end

  test "a run waiting to recreate NEW ends as done, counted by OLD's job", c do
    runner = Brando.Factory.insert(:random_user)
    # Only this test's images are in the run
    Repo.update_all(from(i in Image, where: is_nil(i.deleted_at)), set: [config_target: nil])
    old = Brando.ImageFileFixtures.file_image("a", {800, 600})
    new = Brando.ImageFileFixtures.file_image("b", {1600, 1200})
    Work.subscribe(runner)

    {:ok, proposal} = Proposals.propose([%ReplaceImageFile{asset: {:image, old.id}, with: {:image, new.id}}], c.user)
    assert proposal.problems == []

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _walk} = Processing.recreate_sizes_for_images(runner)
      Oban.drain_queue(queue: :default, with_recursion: true)
      assert SizeRun.remaining() == 2

      assert {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      assert {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)

      Oban.drain_queue(queue: :image_processing, with_scheduled: true)
      Oban.drain_queue(queue: :default, with_scheduled: true, with_recursion: true)
    end)

    assert_receive {:work, "image-sizes", :finished, %Work{total: 2, done: 2, failed: 0}}, 1000
    refute SizeRun.running?()
  end
end

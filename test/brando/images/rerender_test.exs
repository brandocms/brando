defmodule Brando.Images.RerenderTest do
  # Saved entries serve their stored render. When an image's processing
  # changes what a render reads from it (its sizes, formats, dimensions), the
  # entries that show it render again: held until a size run's images are
  # done, so a page renders once per run, and in the bulk lane for one image
  # (#3735).
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Content.Blocks
  alias Brando.Content.RenderQueue
  alias Brando.Content.RenderRun
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.ImageFileFixtures
  alias Brando.Images.Image
  alias Brando.Images.Processing
  alias Brando.Images.Rerender
  alias Brando.Images.SizeRun
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures
  alias Brando.Worker
  alias BrandoAdmin.Work

  defmodule VixProcessor do
    @moduledoc false
    def get_dominant_color(_path), do: "#123456"
    defdelegate process_image(conversion_parameters), to: Brando.Images.Processor.Vix
  end

  @renderer "Brando.Worker.EntryRenderer"
  @with_2xlarge [{"small", "700w"}, {"medium", "1100w"}, {"large", "1700w"}, {"xlarge", "2100w"}, {"2xlarge", "2400w"}]

  setup do
    images_config = Application.get_env(:brando, Brando.Images, [])
    put_test_env(Brando.Images, Keyword.put(images_config, :processor_module, VixProcessor))
    user = Factory.insert(:random_user)
    # Only this test's images: the fixtures' (the user's avatar) are not configured
    Repo.update_all(from(i in Image, where: is_nil(i.deleted_at)), set: [config_target: nil])
    Work.subscribe(user)
    {:ok, user: user}
  end

  # The site's image settings gain a size, and its srcset with it
  defp add_2xlarge do
    config = Application.get_env(:brando, Brando.Images, [])
    default = Keyword.fetch!(config, :default_config)

    default = %{
      default
      | sizes: {:standard, %{"2xlarge" => %{"size" => "2400", "quality" => 70}}},
        srcset: %{default: @with_2xlarge}
    }

    put_test_env(Brando.Images, Keyword.merge(config, default_config: default, default_srcset: %{default: @with_2xlarge}))
  end

  # The site's "large" size, at another width under the same key
  defp resize_large(size) do
    config = Application.get_env(:brando, Brando.Images, [])
    default = Keyword.fetch!(config, :default_config)
    sizes = {:standard, %{"large" => %{"size" => size, "quality" => 75}}}
    put_test_env(Brando.Images, Keyword.put(config, :default_config, %{default | sizes: sizes}))
  end

  # Processed from the fixture original, with no dimensions recorded, so the
  # srcset keeps each width as the config writes it
  defp image do
    Factory.insert(:image, path: "images/avatars/27i97a.jpeg", width: nil, height: nil)
  end

  defp module!(user, code, opts \\ []) do
    ProposalFixtures.module!(user, "Module #{System.unique_integer([:positive])}", code, opts)
  end

  defp block!(user, module, attrs) do
    %Block{}
    |> Block.recursive_block_changeset(
      Map.merge(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => module.id,
          "sequence" => 0,
          "creator_id" => user.id,
          "source" => to_string(Page.Blocks)
        },
        attrs
      ),
      user
    )
    |> Repo.insert!()
  end

  defp page!(user, attrs \\ %{}) do
    Factory.insert(:page, Map.merge(%{creator: user, uri: "p-#{System.unique_integer([:positive])}"}, attrs))
  end

  defp show!(page, block) do
    Repo.insert!(struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: 0}))
    {:ok, page} = Blocks.render_entry(Page, page.id)
    page
  end

  defp ref_block(user, ref_data, image_key) do
    module =
      module!(user, ~s(<div>{% ref refs.photo %}</div>),
        refs: [ProposalFixtures.ref("photo", %{type: ref_data["type"], data: %{}})]
      )

    block!(user, module, %{
      "refs" => [Map.merge(%{"uid" => Brando.Utils.generate_uid(), "name" => "photo", "sequence" => 0}, image_key)]
    })
  end

  # A page showing `image` in a picture ref
  defp in_ref(user, image) do
    block = ref_block(user, %{"type" => "picture"}, %{"image_id" => image.id, "data" => picture()})
    show!(page!(user), block)
  end

  defp picture, do: %{"type" => "picture", "data" => %{}}

  # A page showing `image` in a block's image variable
  defp in_var(user, image) do
    module = module!(user, ~s(<div>{% picture photo { srcset: 'default' } %}</div>))
    block = block!(user, module, %{})
    Repo.insert!(%Brando.Content.Var{type: :image, key: "photo", label: "Photo", block_id: block.id, image_id: image.id})
    show!(page!(user), block)
  end

  # A page showing `image` in a gallery ref
  defp in_gallery(user, image) do
    gallery = Factory.insert(:gallery)
    Factory.insert(:gallery_object, gallery: gallery, gallery_id: gallery.id, image: image, image_id: image.id)

    block =
      ref_block(user, %{"type" => "gallery"}, %{
        "gallery_id" => gallery.id,
        "data" => %{"type" => "gallery", "data" => %{}}
      })

    show!(page!(user), block)
  end

  # A page holding `image` in its meta image field, which it shows itself,
  # and a page listing it through its identifier, showing that image too
  defp in_field(user, image) do
    own = module!(user, ~s(<div>{% picture entry.meta_image { srcset: 'default' } %}</div>))
    owner = page!(user, %{meta_image_id: image.id})
    {:ok, _} = Brando.Content.create_identifier(Page, owner)
    owner = show!(owner, block!(user, own, %{}))
    {:ok, identifier} = Brando.Content.get_identifier(Page, owner)

    card =
      module!(
        user,
        ~S"""
        {% assign e = card.identifier | get_entry %}{% if e %}{% picture e.meta_image { srcset: 'default' } %}{% endif %}
        """,
        vars: [%{type: :link, key: "card", label: "Card", link_type: :identifier, creator_id: user.id}]
      )

    block = block!(user, card, %{})

    Repo.insert!(%Brando.Content.Var{
      type: :link,
      key: "card",
      label: "Card",
      link_type: :identifier,
      identifier_id: identifier.id,
      block_id: block.id,
      creator_id: user.id
    })

    {owner, show!(page!(user), block)}
  end

  defp renders, do: Repo.all(from(j in Oban.Job, where: j.worker == @renderer, order_by: j.id))

  defp renders_of(page),
    do: Enum.filter(renders(), &(&1.args["entry_id"] == page.id))

  # The walk, then the images
  defp run_images(user) do
    assert {:ok, _} = Processing.recreate_sizes_for_images(user)
    Oban.drain_queue(queue: :default)
    Oban.drain_queue(queue: :image_processing, with_scheduled: true)
  end

  # The watcher's looks, and the renders it releases
  defp watch, do: Oban.drain_queue(queue: :default, with_scheduled: true, with_recursion: true)

  defp work(user) do
    BrandoAdmin.Work.Registry.sync()
    Work.get(user, SizeRun.work_key())
  end

  describe "a recreate with a size added" do
    test "renders each entry showing the image again, with the new srcset", %{user: user} do
      image = image()
      pages = [in_ref(user, image), in_var(user, image), in_gallery(user, image)]
      {owner, listing} = in_field(user, image)
      pages = pages ++ [owner, listing]

      for page <- pages do
        assert page.rendered_blocks =~ "/xlarge/"
        refute page.rendered_blocks =~ "2xlarge"
      end

      add_2xlarge()

      Oban.Testing.with_testing_mode(:manual, fn ->
        run_images(user)
        assert "2xlarge" in Map.keys(Repo.get!(Image, image.id).sizes)
        watch()
      end)

      for page <- pages do
        html = Repo.reload!(page).rendered_blocks
        assert html =~ ~r{/2xlarge/27i97a\.jpe?g 2400w}, "page #{page.id}: #{html}"
        # Rendered once
        assert [%{state: "completed"}] = renders_of(page)
      end

      assert_receive {:work, "image-sizes", :finished, %Work{message: "1 image recreated, 5 pages updated"}}
    end
  end

  # A page showing each of `images` in a picture ref of its own block
  defp page_with(user, images) do
    page = page!(user)

    for {image, sequence} <- Enum.with_index(images) do
      block = ref_block(user, %{"type" => "picture"}, %{"image_id" => image.id, "data" => picture()})
      Repo.insert!(struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: sequence}))
    end

    page
  end

  defp jobs(worker), do: all_enqueued(worker: worker)
  defp delete_job(job), do: Repo.delete_all(from(j in Oban.Job, where: j.id == ^job.id))

  # Runs the watcher's next look on its row, as Oban would: the row is
  # executing while it looks, and then done, or waits for its next look.
  # `args` stands in for what the job was fetched with.
  defp look(args \\ nil) do
    {result, job} = look_executing(args)
    ack(job, result)
    if match?({:snooze, _}, result), do: :ok, else: result
  end

  # The look, with its row left executing
  defp look_executing(args \\ nil) do
    [job] = jobs(Worker.ImageMaintenance)
    now = DateTime.utc_now()
    Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: "executing", attempted_at: now])
    job = %{Repo.get!(Oban.Job, job.id) | state: "executing", attempted_at: now}
    {Worker.ImageMaintenance.perform(if(args, do: %{job | args: args}, else: job)), job}
  end

  defp ack(job, {:snooze, seconds}) do
    at = DateTime.add(DateTime.utc_now(), seconds)
    Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: "scheduled", scheduled_at: at])
  end

  defp ack(job, _result) do
    Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id),
      set: [state: "completed", completed_at: DateTime.utc_now()]
    )
  end

  defp watchers do
    Repo.all(
      from(j in Oban.Job,
        where: j.worker == "Brando.Worker.ImageMaintenance" and fragment("? @> ?", j.args, ^%{"watch" => true})
      )
    )
  end

  defp run_id do
    [%{args: %{"run" => run}}] = jobs(Worker.ImageMaintenance)
    run
  end

  defp forget(user) do
    Work.fail(user, SizeRun.work_key())
    assert_receive {:work, "image-sizes", :failed, %Work{}}
  end

  describe "a size run" do
    test "renders a page showing many of its images once, after the last image", %{user: user} do
      images = for _ <- 1..3, do: image()
      page = page_with(user, images)

      Oban.Testing.with_testing_mode(:manual, fn ->
        run_images(user)
        run = run_id()

        # Held under the run's key and tagged with it, one for the page
        assert [render] = renders_of(page)
        assert render.state == "scheduled"
        assert render.priority == RenderQueue.bulk_priority()
        assert render.meta["brando_hold"] == [SizeRun.hold_key(run)]
        assert run in render.meta["brando_runs"]

        watch()
      end)

      assert [%{state: "completed"}] = renders_of(page)
      assert_receive {:work, "image-sizes", :finished, %Work{message: "3 images recreated, 1 page updated"}}
    end

    test "goes from its images to its pages, and ends after the last render", %{user: user} do
      page = page_with(user, [image()])

      Oban.Testing.with_testing_mode(:manual, fn ->
        run_images(user)
        assert %Work{status: :running, total: 1, done: 1, message: "Recreating image sizes"} = work(user)

        # The images are done: the run's renders are released
        assert :ok = look()
        assert [%{state: "available"}] = renders_of(page)
        assert SizeRun.status() == %{running?: true, remaining: 0, pages: 1}

        # A moment later, the pages
        assert :ok = look()
        assert %Work{status: :running, total: 1, done: 0, failed: 0, message: "Updating pages"} = work(user)
        assert SizeRun.running?()
        assert {:error, :already_running} = Processing.recreate_sizes_for_images(user)

        # A node restarted meanwhile says the step again
        forget(user)
        assert :ok = look()
        assert %Work{status: :running, total: 1, done: 0, message: "Updating pages"} = work(user)

        # The page's render, and the cascade the image's save queues
        assert %{failure: 0} = Oban.drain_queue(queue: :default)
        assert :ok = look()
        assert jobs(Worker.ImageMaintenance) == []
        refute SizeRun.running?()
      end)

      assert_receive {:work, "image-sizes", :finished, %Work{message: "1 image recreated, 1 page updated"}}
    end

    test "that dies leaves its held renders to run by themselves", %{user: user} do
      page = page_with(user, [image()])

      Oban.Testing.with_testing_mode(:manual, fn ->
        run_images(user)
        # The watcher is gone (a node that went down, a job deleted)
        [watcher] = jobs(Worker.ImageMaintenance)
        delete_job(watcher)
        refute SizeRun.running?()

        assert [%{state: "scheduled", scheduled_at: at}] = renders_of(page)
        held = DateTime.diff(at, DateTime.utc_now(), :millisecond)
        assert held > RenderQueue.max_hold() - :timer.minutes(1) and held <= RenderQueue.max_hold()

        # When the hold runs out, Oban's stager makes them available
        assert %{failure: 0} = Oban.drain_queue(queue: :default, with_scheduled: true)
      end)

      assert [%{state: "completed"}] = renders_of(page)
    end

    test "with a page whose render fails ends as failed, saying so", %{user: user} do
      page = page_with(user, [image()])

      Oban.Testing.with_testing_mode(:manual, fn ->
        run_images(user)
        # A block template fails: the renderer cancels its job
        [render] = renders_of(page)
        Repo.update_all(from(j in Oban.Job, where: j.id == ^render.id), set: [state: "cancelled"])
        watch()
      end)

      assert_receive {:work, "image-sizes", :failed,
                      %Work{failed: 0, message: "1 image recreated, 1 page could not be updated"}}

      refute SizeRun.running?()
    end

    test "with an image that nothing shows renders nothing", %{user: user} do
      image()

      Oban.Testing.with_testing_mode(:manual, fn ->
        run_images(user)
        assert renders() == []
        watch()
      end)

      assert_receive {:work, "image-sizes", :finished, %Work{message: "1 image recreated"}}
    end

    # The image editor saves a focal point while the run's job for the
    # image waits: the job that takes its place holds the renders too
    test "with an image queued again while it waits still holds its page", %{user: user} do
      image = image()
      page = page_with(user, [image])

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Processing.recreate_sizes_for_images(user)
        Oban.drain_queue(queue: :default)
        assert {:ok, _} = Processing.queue_processing(image, user, [], silent: true)
        Oban.drain_queue(queue: :image_processing, with_scheduled: true)

        assert [%{state: "scheduled", meta: %{"brando_hold" => [_]}}] = renders_of(page)
        watch()
      end)

      assert [%{state: "completed"}] = renders_of(page)
    end

    test "neither queues nor releases another site's renders", %{user: user} do
      page = page_with(user, [image()])
      other = "tenant_other_live"

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Processing.recreate_sizes_for_images(user)
        Oban.drain_queue(queue: :default)
        run = run_id()

        # Held under the same key, and tagged with the run, in another site
        put_test_env(:tenancy_mode, :multi)

        Brando.Tenant.with_prefix(other, fn ->
          Brando.Content.RenderRun.within_run(run, fn ->
            RenderQueue.enqueue_map(%{Page => [page.id]}, hold: SizeRun.hold_key(run))
          end)
        end)

        put_test_env(:tenancy_mode, :none)
        Oban.drain_queue(queue: :image_processing, with_scheduled: true)
        assert :ok = look()
        assert :ok = look()

        by_site = Map.new(renders_of(page), &{&1.args["tenant_prefix"], &1.state})
        assert by_site == %{nil => "available", other => "scheduled"}
        assert %Work{total: 1, message: "Updating pages"} = work(user)

        Repo.delete_all(from(j in Oban.Job, where: fragment("?->>'tenant_prefix' = ?", j.args, ^other)))
        watch()
      end)

      assert_receive {:work, "image-sizes", :finished, %Work{message: "1 image recreated, 1 page updated"}}
    end

    # A walk that closes while the watcher looks: the count is in its row
    # (#3742 review)
    test "reads its images' count from its row, not from arguments fetched before the walk closed", %{user: user} do
      page_with(user, [image()])

      Oban.Testing.with_testing_mode(:manual, fn ->
        run_images(user)
        [watcher] = jobs(Worker.ImageMaintenance)
        assert watcher.args["queued"] == 1

        assert :ok = look(Map.delete(watcher.args, "queued"))
        watch()
      end)

      assert_receive {:work, "image-sizes", :finished, %Work{message: "1 image recreated, 1 page updated"}}
    end

    test "counts a page whose render was pruned between two looks as updated", %{user: user} do
      page = page_with(user, [image()])

      Oban.Testing.with_testing_mode(:manual, fn ->
        run_images(user)
        assert :ok = look()
        assert :ok = look()
        assert %Work{total: 1, done: 0, message: "Updating pages"} = work(user)

        # Rendered, and deleted by the Pruner, before the next look
        [render] = renders_of(page)
        delete_job(render)
        watch()
      end)

      assert_receive {:work, "image-sizes", :finished, %Work{message: "1 image recreated, 1 page updated"}}
    end

    test "keeps one job row through its looks", %{user: user} do
      page_with(user, [image()])

      Oban.Testing.with_testing_mode(:manual, fn ->
        run_images(user)
        assert :ok = look()
        assert :ok = look()
        assert :ok = look()
        assert [_watcher] = watchers()
      end)
    end

    test "with pages that never render ends as failed after 30 minutes in which none did", %{user: user} do
      page = page_with(user, [image()])

      Oban.Testing.with_testing_mode(:manual, fn ->
        run_images(user)
        assert :ok = look()
        assert :ok = look()

        # The queue is paused: no page has been updated for half an hour
        [watcher] = jobs(Worker.ImageMaintenance)
        since = DateTime.utc_now() |> DateTime.add(-31, :minute) |> DateTime.to_unix()
        args = put_in(watcher.args, ["pages", "since"], since)
        Repo.update_all(from(j in Oban.Job, where: j.id == ^watcher.id), set: [args: args])

        look()
        refute SizeRun.running?()
        # The render stays queued
        assert [%{state: "available"}] = renders_of(page)
      end)

      assert_receive {:work, "image-sizes", :failed,
                      %Work{message: "1 image recreated, 1 page is still waiting to be updated"}}
    end

    # The Utilities row reads the jobs when the work ends
    test "is over for every admin once its work has ended, while its watcher's last look runs", %{user: user} do
      page_with(user, [image()])

      Oban.Testing.with_testing_mode(:manual, fn ->
        run_images(user)
        assert :ok = look()
        assert :ok = look()
        assert %{failure: 0} = Oban.drain_queue(queue: :default)

        {:ok, job} = look_executing()
        assert_receive {:work, "image-sizes", :finished, %Work{}}
        refute SizeRun.running?()
        ack(job, :ok)
      end)
    end

    test "counts a page whose failed render was queued again and rendered as updated", %{user: user} do
      page = page_with(user, [image()])

      Oban.Testing.with_testing_mode(:manual, fn ->
        run_images(user)
        run = run_id()
        [render] = renders_of(page)
        Repo.update_all(from(j in Oban.Job, where: j.id == ^render.id), set: [state: "discarded"])

        # Queued again within the run (an image of the run processed again)
        RenderRun.within_run(run, fn ->
          RenderQueue.enqueue_map(%{Page => [page.id]}, hold: SizeRun.hold_key(run))
        end)

        assert [%{state: "discarded"}, %{state: "scheduled"}] = renders_of(page)
        watch()
      end)

      assert_receive {:work, "image-sizes", :finished, %Work{message: "1 image recreated, 1 page updated"}}
    end

    # Its files match its config: only its config fingerprint is written
    test "renders the entries of an image it adopts", %{user: user} do
      image = ImageFileFixtures.unrecorded_image("rerender-#{System.unique_integer([:positive])}")
      page = page_with(user, [image])

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Processing.recreate_sizes_for_changed_images(user)
        Oban.drain_queue(queue: :default)
        run = run_id()
        assert Repo.get!(Image, image.id).config_fingerprint
        assert jobs(Worker.ImageProcessor) == []

        assert [%{state: "scheduled", meta: %{"brando_hold" => [hold]}}] = renders_of(page)
        assert hold == SizeRun.hold_key(run)
        watch()
      end)

      assert [%{state: "completed"}] = renders_of(page)
      assert_receive {:work, "image-sizes", :finished, %Work{message: "No images to recreate, 1 page updated"}}
    end
  end

  describe "one image processed outside a run" do
    test "renders its entries in the bulk lane, not held", %{user: user} do
      image = image()
      page = page_with(user, [image])

      Oban.Testing.with_testing_mode(:manual, fn ->
        # As the image editor queues it
        assert {:ok, _} = Processing.queue_processing(image, user, [], silent: true)
        Oban.drain_queue(queue: :image_processing)
      end)

      assert [render] = renders_of(page)
      assert render.state == "available"
      assert render.priority == RenderQueue.bulk_priority()
      refute Map.has_key?(render.meta, "brando_hold")
      refute SizeRun.running?()
    end

    test "renders its entries when recreated for its config target at once", %{user: user} do
      page = page_with(user, [image()])

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, [_id]} = Processing.recreate_sizes_for_image_field("default", :system)
      end)

      assert [%{state: "available"}] = renders_of(page)
    end

    test "renders nothing when processing changed nothing a render reads", %{user: user} do
      image = image()
      page = page_with(user, [image])

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Processing.queue_processing(image, user, [], silent: true)
        Oban.drain_queue(queue: :image_processing)
        assert [first] = renders_of(page)
        delete_job(first)

        # The same settings again: the same sizes, formats and dimensions
        assert {:ok, _} = Processing.queue_processing(image, user, [], silent: true)
        Oban.drain_queue(queue: :image_processing)
        assert renders_of(page) == []
      end)
    end

    # An operator changes "large" from 1700 to 2000: the files change, and
    # their paths, the formats and the dimensions do not. The srcset reads
    # the widths from the config.
    test "renders its entries when a size changed under the same key", %{user: user} do
      image = image()
      page = page_with(user, [image])

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Processing.queue_processing(image, user, [], silent: true)
        Oban.drain_queue(queue: :image_processing)
        Enum.each(renders_of(page), &delete_job/1)
        sizes = Repo.get!(Image, image.id).sizes

        resize_large("2000")
        assert {:ok, _} = Processing.queue_processing(image, user, [], silent: true)
        Oban.drain_queue(queue: :image_processing)

        assert Repo.get!(Image, image.id).sizes == sizes
        assert [_render] = renders_of(page)
      end)
    end

    # A completed callback raises for a retry; so do a timeout and a node
    # stopping. The retry reads the stored sizes as they were before it.
    test "renders its entries when its job fails after the sizes were stored", %{user: user} do
      image = image()
      page = page_with(user, [image])
      config = Application.get_env(:brando, Brando.Images, [])
      default = Keyword.fetch!(config, :default_config)
      callback = fn _image, _user -> raise "the callback failed" end
      put_test_env(Brando.Images, Keyword.put(config, :default_config, Map.put(default, :completed_callback, callback)))

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Processing.queue_processing(image, user, [], silent: true)
        assert %{failure: 1} = Oban.drain_queue(queue: :image_processing)
      end)

      assert [_render] = renders_of(page)
    end
  end

  describe "the entries that show an image" do
    test "are each listed once, out of the trash, and only those with blocks", %{user: user} do
      image = image()
      twice = page_with(user, [image, image])
      trashed = page_with(user, [image])
      Repo.update_all(from(p in Page, where: p.id == ^trashed.id), set: [deleted_at: DateTime.utc_now()])
      # A user's avatar has no stored render
      avatar = Factory.insert(:random_user)
      Repo.update_all(from(u in Brando.Users.User, where: u.id == ^avatar.id), set: [avatar_id: image.id])

      assert Rerender.entries([image.id]) == %{Page => [twice.id]}
    end

    test "leave out a page in the trash that holds the image in a page variable", %{user: user} do
      image = image()
      page = page!(user)
      Repo.insert!(%Var{type: :image, key: "photo", label: "Photo", page_id: page.id, image_id: image.id})
      Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [deleted_at: DateTime.utc_now()])

      assert Rerender.entries([image.id]) == %{}
    end

    # A size changed under its key changes the srcset's widths and the
    # crop, read from the config the fingerprint is of
    test "a changed config fingerprint changes what a render reads" do
      image = image()
      assert Rerender.changed?(image, %{image | config_fingerprint: "0123456789ab"})
      assert Rerender.changed?(image, %{image | sizes: Map.put(image.sizes, "2xlarge", "image/2xlarge/1.jpg")})
      assert Rerender.changed?(image, %{image | width: 1200})
    end
  end
end

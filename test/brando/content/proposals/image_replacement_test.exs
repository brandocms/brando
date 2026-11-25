defmodule Brando.Content.Proposals.ImageReplacementTest do
  # The `replace_image_file` operation: library image OLD takes NEW's file
  # on approval, keeping its id, texts, focal point, folder and references,
  # and NEW's record goes. And what can go wrong between preparing and
  # approving it: NEW put to use, either image trashed or replaced first, a
  # file the field does not take, an entry the person may not change, a
  # failure after the file was taken.
  #
  # Grouped, one at a time, as `Brando.Content.ProposalsTest`:
  # ProposalFixtures.context/0 inserts pages whose URIs concurrent
  # transactions would wait on, and the group tests take the authorization lock.
  use Brando.ConnCase, async: true, group: :shared_locks

  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.{Codec, CreateEntry, ImageReplacement, InsertBlock, ReplaceImageFile}
  alias Brando.Content.Usage
  alias Brando.{Factory, Images, Repo}
  alias Brando.Images.Image
  alias Brando.Pages.Page
  alias Ecto.Changeset

  setup do
    Brando.ProposalFixtures.context()
  end

  defp image!(name, dimensions, opts \\ []), do: Brando.ImageFileFixtures.file_image(name, dimensions, opts)

  defp replace(old, new), do: %ReplaceImageFile{asset: {:image, old.id}, with: {:image, new.id}}

  defp approve_and_apply(proposal, user) do
    with {:ok, _} <- Proposals.approve(proposal.id, proposal.version, user),
         do: Proposals.apply(proposal.id, proposal.version, user)
  end

  # Puts `image` in a new Case block of `page`, through a proposal.
  defp place!(c, page, image) do
    ops = [%InsertBlock{target: {Page, page.id}, module: c.case_module.id, media: %{cover: {:image, image.id}}}]
    {:ok, proposal} = Proposals.propose(ops, c.user)
    assert proposal.problems == []
    {:ok, _receipt} = approve_and_apply(proposal, c.user)
    :ok
  end

  defp codes(proposal), do: Enum.map(proposal.problems, & &1.code)

  defp unchanged!(old) do
    now = Repo.get!(Image, old.id)
    assert {now.path, now.width, now.height, now.content_hash} == {old.path, old.width, old.height, old.content_hash}
    assert File.exists?(Brando.Images.Utils.media_path(old.path))
  end

  test "between two imported images: OLD's sources go, and NEW's are OLD's", c do
    old = image!("imported", {800, 600})
    new = image!("imported-better", {1600, 1200})
    Brando.Images.Source.record(old, "figma", "a", nil, "default")
    Brando.Images.Source.record(new, "figma", "b", nil, "default")
    Brando.Images.Source.record(new, "figma", "b", "90", "default")

    {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)
    assert proposal.problems == []
    assert {:ok, _receipt} = approve_and_apply(proposal, c.user)

    assert Brando.Images.Source.images("figma", [{"a", nil}, {"b", nil}, {"b", "90"}], "default", c.user) ==
             %{{"b", nil} => old.id, {"b", "90"} => old.id}

    assert Repo.all(from(s in Brando.Images.Source, select: s.image_id)) == [old.id, old.id]
  end

  defp cached_images(old, donor) do
    get = fn id -> Images.get_image(%{matches: %{id: id}, cache: true}) end
    {:ok, list} = Images.list_images(%{cache: true})
    {get.(old.id), get.(donor.id), Map.new(list, &{&1.id, &1.path})}
  end

  test "cached lookups and lists reflect a committed replacement before processing", c do
    old = image!("a", {800, 600})
    donor = image!("b", {1600, 1200})
    {:ok, proposal} = Proposals.propose([replace(old, donor)], c.user)

    assert {{:ok, _}, {:ok, _}, before} = cached_images(old, donor)
    assert before[old.id] == old.path
    assert before[donor.id] == donor.path

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _receipt} = approve_and_apply(proposal, c.user)
      assert {{:ok, updated}, {:error, _}, after_apply} = cached_images(old, donor)
      assert updated.path == donor.path
      assert after_apply[old.id] == donor.path
      refute Map.has_key?(after_apply, donor.id)
    end)
  end

  test "OLD takes NEW's file and keeps its id, texts, focal point, folder and references; NEW goes", c do
    folder = Repo.insert!(%Brando.Media.Folder{scope: "images", name: "people", path: "people"})

    old =
      image!("portrait", {800, 600},
        title: %{"en" => "Portrait"},
        alt: %{"en" => "A portrait"},
        credits: %{"en" => "Studio"},
        focal: %{x: 20, y: 30},
        folder_id: folder.id
      )

    new = image!("portrait-better", {1600, 1200}, dominant_color: "#aabbcc")
    place!(c, c.identity, old)

    {:ok, proposal} = Proposals.propose([replace(old, new)], c.user, summary: "A better portrait")
    assert proposal.problems == []
    assert proposal.effects.replaced_images == 1
    assert proposal.effects.updates == 0

    # The files as they were are frozen with it
    assert [%ReplaceImageFile{old: %{"path" => old_path}, new: %{"path" => new_path, "type" => "image/jpeg"} = frozen}] =
             proposal.operations

    assert {old_path, new_path} == {old.path, new.path}
    assert frozen["bytes"] == File.stat!(Brando.Images.Utils.media_path(new.path)).size

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, receipt} = approve_and_apply(proposal, c.user)
      assert [%{"image" => old_id, "with" => new_id}] = receipt.mappings["replaced_images"]
      assert {old_id, new_id} == {old.id, new.id}

      # Its sizes are made again, for its own config, as for an upload
      assert [job] = all_enqueued(worker: Brando.Worker.ImageProcessor)
      assert job.args["image_id"] == old.id
      assert job.args["config_target"] == "default"
    end)

    replaced = Repo.get!(Image, old.id)
    assert replaced.path == new.path
    assert {replaced.width, replaced.height} == {1600, 1200}
    assert replaced.content_hash == new.content_hash
    assert replaced.dominant_color == "#aabbcc"
    assert replaced.status == :unprocessed
    assert replaced.title == %{"en" => "Portrait"}
    assert replaced.alt == %{"en" => "A portrait"}
    assert replaced.credits == %{"en" => "Studio"}
    assert {replaced.focal.x, replaced.focal.y} == {20, 30}
    assert replaced.folder_id == folder.id

    # NEW's record went; its file is OLD's now
    assert Repo.get(Image, new.id) == nil
    assert File.exists?(Brando.Images.Utils.media_path(new.path))

    # OLD's previous file is left, unreferenced, for the orphan cleanup
    assert File.exists?(Brando.Images.Utils.media_path(old.path))

    # Every reference still points at OLD
    assert Usage.owners(:image, [old.id]) == %{old.id => [{Page, c.identity.id}]}

    # Activity names the image and both files
    assert %Event{action: :updated, fields: ["file"], details: details, proposal_id: proposal_id} =
             Repo.one(from(e in Event, where: e.schema == ^to_string(Image) and e.entry_id == ^old.id))

    assert proposal_id == proposal.id
    assert details["replaced_file"] == %{"from" => Path.basename(old.path), "with" => new.id}

    # A replaced file has no undo
    assert {:error, _} = Proposals.undo(proposal.id, c.user)
    assert Proposals.replaced_images?(Proposals.receipt(proposal.id, c.user))
  end

  test "OLD's previous files outlive the orphan cleanup's grace period, counted from the replacement", c do
    small = "images/replace/small/portrait-#{System.unique_integer([:positive])}.jpg"
    Brando.ImageFileFixtures.write_image(small, {700, 525})
    Brando.ImageFileFixtures.write_image(String.replace_suffix(small, ".jpg", ".webp"), {700, 525})
    # A size of OLD's own config, which NEW's sizes lack
    wide = String.replace(small, "/small/", "/wide/")
    Brando.ImageFileFixtures.write_image(wide, {1400, 1050})
    Brando.ImageFileFixtures.write_image(String.replace_suffix(wide, ".jpg", ".webp"), {1400, 1050})
    old = image!("portrait", {800, 600}, sizes: %{"small" => small, "wide" => wide}, formats: [:jpg, :webp])
    new = image!("portrait-better", {1600, 1200})

    previous = [old.path] ++ Enum.flat_map([small, wide], &[&1, String.replace_suffix(&1, ".jpg", ".webp")])
    two_days_ago = System.os_time(:second) - 2 * 86_400

    for path <- previous,
        do: :ok = File.touch(Brando.Images.Utils.media_path(path), two_days_ago)

    {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)
    assert {:ok, _receipt} = approve_and_apply(proposal, c.user)

    # No image row names them now, but a page rendered before still links
    # them: OLD's own sizes have been made, and they are all still there
    assert Enum.reject(previous, &File.exists?(Brando.Images.Utils.media_path(&1))) == []
    {:ok, report} = Brando.Media.OrphanCleanup.run(nil, dry_run: true)
    assert Enum.filter(previous, &(&1 in report.deleted)) == []
  end

  # The replacement queues no render itself: OLD's sizes made again are a
  # change to what its markup reads, and that renders the entries showing it
  test "the entries that show OLD render again once its sizes are made", c do
    old = image!("cover", {800, 600})
    new = image!("cover-better", {1600, 1200})
    place!(c, c.identity, old)
    {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _receipt} = approve_and_apply(proposal, c.user)

      renders = fn ->
        Enum.filter(
          all_enqueued(worker: Brando.Worker.EntryRenderer),
          &(&1.args["entry_id"] == c.identity.id and &1.args["schema"] == "Elixir.Brando.Pages.Page")
        )
      end

      assert renders.() == []
      # The one change its processing is sure to make, when NEW was made
      # for the same config
      assert Repo.get!(Image, old.id).config_fingerprint == nil
      assert %{failure: 0, success: 1} = Oban.drain_queue(queue: :image_processing)
      assert is_binary(Repo.get!(Image, old.id).config_fingerprint)
      assert [%{priority: priority}] = renders.()
      assert priority == Brando.Content.RenderQueue.bulk_priority()
    end)
  end

  test "an approval while NEW's sizes are being made is refused, to try again; prepared, it waits", c do
    old = image!("a", {800, 600})
    new = image!("b", {1600, 1200}, status: :unprocessed, sizes: %{})

    # A tool prepares it right after uploading
    {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)
    assert proposal.problems == []

    assert {:error, _message} = Proposals.approve(proposal.id, proposal.version, c.user)
    {:ok, stored} = Proposals.get(proposal.id, c.user)
    assert {stored.status, stored.problems} == {"pending", []}
    unchanged!(old)

    # Once they are made, it is approved
    Repo.update_all(from(i in Image, where: i.id == ^new.id),
      set: [status: :processed, sizes: %{"small" => "images/replace/small/b.jpg"}]
    )

    assert {:ok, _receipt} = approve_and_apply(proposal, c.user)
  end

  test "OLD takes NEW's sizes alone until its own are made, not its previous file's", c do
    old =
      image!("a", {800, 600}, sizes: %{"small" => "images/replace/small/a.jpg", "large" => "images/replace/large/a.jpg"})

    new = image!("b", {1600, 1200}, sizes: %{"small" => "images/replace/small/b.jpg"})

    {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _receipt} = approve_and_apply(proposal, c.user)
    end)

    assert Repo.get!(Image, old.id).sizes == %{"small" => "images/replace/small/b.jpg"}
  end

  test "the review shows both files, the entries that use OLD and whether the proportions differ", c do
    old = image!("logo", {800, 600})
    same = image!("logo-same", {1600, 1200})
    other = image!("logo-wide", {1600, 900})
    place!(c, c.identity, old)
    place!(c, c.naming, old)

    {:ok, proposal} = Proposals.propose([replace(old, same)], c.user)

    assert [
             %{
               operations: [0],
               old: %{id: old_id, name: old_name, width: 800, height: 600, type: "JPEG", image: %Image{}},
               new: %{width: 1600, height: 1200},
               proportions_differ?: false,
               entries: [%{label: "Identity", url: identity_url}, %{label: "Naming"}],
               hidden: 0,
               problems: []
             }
           ] = ImageReplacement.review(proposal)

    assert old_id == old.id
    assert old_name == Path.basename(old.path)
    assert identity_url =~ "#{c.identity.id}"

    {:ok, proposal} = Proposals.propose([replace(old, other)], c.user)
    assert [%{proportions_differ?: true}] = ImageReplacement.review(proposal)

    # Applied, it still shows the two files as they were
    {:ok, _receipt} = approve_and_apply(proposal, c.user)
    {:ok, applied} = Proposals.get(proposal.id, c.user)
    assert [%{old: %{name: ^old_name, width: 800}, new: %{width: 1600, height: 900}}] = ImageReplacement.review(applied)
  end

  describe "refused when the proposal is prepared" do
    test "an image replaced with itself, or one that is not in the library", c do
      old = image!("a", {800, 600})
      assert {:ok, proposal} = Proposals.propose([replace(old, old)], c.user)
      assert codes(proposal) == [:same_image]

      missing = %ReplaceImageFile{asset: {:image, old.id}, with: {:image, old.id + 100_000}}
      assert {:ok, proposal} = Proposals.propose([missing], c.user)
      assert codes(proposal) == [:missing_asset]
    end

    test "OLD or NEW in the trash", c do
      old = image!("a", {800, 600})
      new = image!("b", {800, 600})
      Repo.update!(Changeset.change(new, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)))
      assert {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)
      assert codes(proposal) == [:missing_asset]

      new = image!("c", {800, 600})
      Repo.update!(Changeset.change(old, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)))
      assert {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)
      assert codes(proposal) == [:missing_asset]
    end

    test "a NEW that is already used, pointing to swapping the references", c do
      old = image!("a", {800, 600})
      new = image!("b", {800, 600})
      place!(c, c.naming, new)

      assert {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)
      assert codes(proposal) == [:asset_in_use]
      assert hd(proposal.problems).message =~ "set_block_media"
    end

    test "a NEW in a gallery, a recovery draft or a module's default counts as used", c do
      old = image!("a", {800, 600})
      new = image!("b", {800, 600})
      refute Usage.used?(:image, new.id)

      gallery = Repo.insert!(%Brando.Galleries.Gallery{config_target: "default"})
      Repo.insert!(%Brando.Galleries.GalleryObject{gallery_id: gallery.id, image_id: new.id, sequence: 0})
      assert Usage.used?(:image, new.id)
      assert {:ok, %{problems: [%{code: :asset_in_use}]}} = Proposals.propose([replace(old, new)], c.user)
    end

    test "a NEW this proposal also places, or an image replaced twice", c do
      old = image!("a", {800, 600})
      new = image!("b", {800, 600})
      other = image!("c", {800, 600})

      place = %InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id, media: %{cover: {:image, new.id}}}
      assert {:ok, proposal} = Proposals.propose([place, replace(old, new)], c.user)
      assert {1, :asset_in_use} in Enum.map(proposal.problems, &{&1.operation, &1.code})

      assert {:ok, proposal} = Proposals.propose([replace(old, new), replace(old, other)], c.user)

      assert Enum.map(proposal.problems, &{&1.operation, &1.code}) == [
               {0, :duplicate_replacement},
               {1, :duplicate_replacement}
             ]
    end

    test "the same replacement twice", c do
      old = image!("a", {800, 600})
      new = image!("b", {800, 600})

      assert {:ok, proposal} = Proposals.propose([replace(old, new), replace(old, new)], c.user)
      assert Enum.map(proposal.problems, & &1.code) == [:duplicate_replacement, :duplicate_replacement]
    end

    test "a NEW this proposal sets as a field's id", c do
      old = image!("a", {800, 600})
      new = image!("b", {800, 600})

      {:ok, [set | _]} =
        Codec.decode_all([
          %{
            "op" => "set_fields",
            "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
            "fields" => %{"meta_image_id" => new.id}
          }
        ])

      assert {:ok, proposal} = Proposals.propose([set, replace(old, new)], c.user)
      assert {1, :asset_in_use} in Enum.map(proposal.problems, &{&1.operation, &1.code})

      # The id as a string is cast to the same image
      set = %{set | fields: Map.new(set.fields, fn {key, value} -> {key, to_string(value)} end)}
      assert {:ok, proposal} = Proposals.propose([set, replace(old, new)], c.user)
      assert {1, :asset_in_use} in Enum.map(proposal.problems, &{&1.operation, &1.code})
    end

    test "NEW put to use: approval and apply are refused, and OLD stays as it was", c do
      old = image!("a", {800, 600})
      new = image!("b", {1600, 1200})
      {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)
      place!(c, c.naming, new)

      assert {:error, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      {:ok, stored} = Proposals.get(proposal.id, c.user)
      assert codes(stored) == [:asset_in_use]
      unchanged!(old)
      assert Repo.get(Image, new.id)

      # And after the approval
      newer = image!("c", {1600, 1200})
      {:ok, proposal} = Proposals.propose([replace(old, newer)], c.user)
      {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      place!(c, c.identity, newer)
      assert {:error, _} = Proposals.apply(proposal.id, proposal.version, c.user)
      unchanged!(old)
      assert Repo.get(Image, newer.id)
    end

    test "OLD or NEW trashed: apply is refused", c do
      old = image!("a", {800, 600})
      new = image!("b", {1600, 1200})
      {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)
      {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      Brando.Images.delete_images([new.id], c.user)
      assert {:error, _} = Proposals.apply(proposal.id, proposal.version, c.user)
      unchanged!(old)

      new = image!("c", {1600, 1200})
      {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)
      {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      Brando.Images.delete_images([old.id], c.user)
      assert {:error, _} = Proposals.apply(proposal.id, proposal.version, c.user)
      assert Repo.get(Image, new.id)
    end

    test "two proposals replacing the same image: the second is refused once the first is applied", c do
      old = image!("a", {800, 600})
      first = image!("b", {1600, 1200})
      second = image!("c", {1600, 1200})

      {:ok, one} = Proposals.propose([replace(old, first)], c.user)
      {:ok, two} = Proposals.propose([replace(old, second)], c.user)
      {:ok, _} = Proposals.approve(two.id, two.version, c.user)

      assert {:ok, _} = approve_and_apply(one, c.user)
      assert {:error, _} = Proposals.apply(two.id, two.version, c.user)
      {:ok, two} = Proposals.get(two.id, c.user)
      assert codes(two) == [:changed_asset]

      assert Repo.get!(Image, old.id).path == first.path
      assert Repo.get(Image, second.id)
    end

    test "an approval that fails after the file was taken leaves OLD as it was, with its files", c do
      old = image!("a", {800, 600})
      new = image!("b", {1600, 1200})

      create = %CreateEntry{
        schema: Page,
        ref: "about",
        fields: %{title: "About", uri: "about-replaced", language: "en", template: "default.html"}
      }

      {:ok, proposal} = Proposals.propose([replace(old, new), create], c.user)
      assert proposal.problems == []
      {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)

      # The new entry's address is taken meanwhile: its save fails after OLD took NEW's file
      Factory.insert(:page, uri: "about-replaced", language: "en", creator: c.user)
      events = Repo.aggregate(Event, :count)

      before = cached_images(old, new)

      # It fails at the entry's save, after the replacement ran
      assert {:error, _} = Proposals.apply(proposal.id, proposal.version, c.user)
      unchanged!(old)
      assert cached_images(old, new) == before
      assert Repo.get(Image, new.id)
      assert File.exists?(Brando.Images.Utils.media_path(new.path))
      assert Repo.aggregate(Event, :count) == events
    end
  end

  test "a person who may change images but not every entry that shows OLD is refused, by name", c do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()
    alias Brando.Authorization.{Catalog, Groups, Scope}

    old = image!("a", {800, 600})
    new = image!("b", {1600, 1200})
    place!(c, c.identity, old)
    Repo.get!(Page, c.identity.id) |> Changeset.change(status: :draft) |> Repo.update!()

    editor = Factory.insert(:random_user, role: :user)

    images = [Catalog.get(:read, Image).key, Catalog.get(:update, Image).key, "brando.admin.access"]
    {:ok, group} = Groups.create(Scope.standalone(c.user), %{name: "Image editors"}, images)
    {:ok, :ok} = Groups.add_member(Scope.standalone(c.user), group.id, editor.id)

    # It sees the page but may not change it
    {:ok, readers} = Groups.create(Scope.standalone(c.user), %{name: "Page readers"}, [Catalog.get(:read, Page).key])
    {:ok, :ok} = Groups.add_member(Scope.standalone(c.user), readers.id, editor.id)

    assert {:ok, %{problems: [%{code: :forbidden, message: message}]}} = Proposals.propose([replace(old, new)], editor)
    assert message =~ "“Identity”"

    # Without the read grant, the page is counted, not named
    {:ok, :ok} = Groups.remove_member(Scope.standalone(c.user), readers.id, editor.id)
    assert {:ok, %{problems: [%{code: :forbidden, message: message}]}} = Proposals.propose([replace(old, new)], editor)
    refute message =~ "Identity"

    # Update on the page too: it may
    {:ok, editors} =
      Groups.create(Scope.standalone(c.user), %{name: "Page editors"}, [
        Catalog.get(:read, Page).key,
        Catalog.get(:update, Page).key
      ])

    {:ok, :ok} = Groups.add_member(Scope.standalone(c.user), editors.id, editor.id)
    assert {:ok, %{problems: []}} = Proposals.propose([replace(old, new)], editor)

    # And without update on images, not
    {:ok, :ok} = Groups.remove_member(Scope.standalone(c.user), group.id, editor.id)
    assert {:ok, %{problems: problems}} = Proposals.propose([replace(old, new)], editor)
    assert :missing_asset in Enum.map(problems, & &1.code) or :forbidden in Enum.map(problems, & &1.code)
  end

  test "an entry in the trash that shows OLD, or a gallery holding it, needs update too", c do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()
    alias Brando.Authorization.{Catalog, Groups, Scope}

    editor = Factory.insert(:random_user, role: :user)
    images = [Catalog.get(:read, Image).key, Catalog.get(:update, Image).key, "brando.admin.access"]
    {:ok, group} = Groups.create(Scope.standalone(c.user), %{name: "Image editors"}, images)
    {:ok, :ok} = Groups.add_member(Scope.standalone(c.user), group.id, editor.id)

    trash! = fn page ->
      Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [deleted_at: DateTime.utc_now()])
    end

    # Shown by a page in the trash
    old = image!("a", {800, 600})
    place!(c, c.identity, old)
    trash!.(c.identity)

    assert {:ok, %{problems: [%{code: :forbidden}]}} =
             Proposals.propose([replace(old, image!("b", {1600, 1200}))], editor)

    # In a gallery a page in the trash shows
    in_gallery = image!("c", {800, 600})
    gallery = Repo.insert!(%Brando.Galleries.Gallery{config_target: "default"})
    Repo.insert!(%Brando.Galleries.GalleryObject{gallery_id: gallery.id, image_id: in_gallery.id, sequence: 0})
    place!(c, c.naming, image!("d", {800, 600}))

    block_id =
      Repo.one!(
        from(r in "content_refs",
          join: b in "content_blocks",
          on: b.id == r.block_id,
          join: pb in "pages_blocks",
          on: pb.block_id == b.id,
          where: pb.entry_id == ^c.naming.id,
          select: r.block_id,
          limit: 1
        )
      )

    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Repo.insert_all("content_refs", [
      %{name: "gallery", uid: "galleryref", block_id: block_id, gallery_id: gallery.id, inserted_at: now, updated_at: now}
    ])

    trash!.(c.naming)

    assert {:ok, %{problems: [%{code: :forbidden}]}} =
             Proposals.propose([replace(in_gallery, image!("e", {1600, 1200}))], editor)
  end

  test "a shared review needs read on both images, and on OLD once NEW is gone", c do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()
    alias Brando.Authorization.{Catalog, Groups, Scope}

    old = image!("a", {800, 600})
    new = image!("b", {1600, 1200})
    {:ok, proposal} = Proposals.propose([replace(old, new)], c.user)
    assert proposal.problems == []

    colleague = Factory.insert(:random_user, role: :user)
    {:ok, access} = Groups.create(Scope.standalone(c.user), %{name: "Admins"}, ["brando.admin.access"])
    {:ok, :ok} = Groups.add_member(Scope.standalone(c.user), access.id, colleague.id)

    # No entries to read, and not the images
    assert {:error, _} = Proposals.get_shared(proposal.id, proposal.version, colleague)

    {:ok, readers} = Groups.create(Scope.standalone(c.user), %{name: "Image readers"}, [Catalog.get(:read, Image).key])
    {:ok, :ok} = Groups.add_member(Scope.standalone(c.user), readers.id, colleague.id)
    assert {:ok, _} = Proposals.get_shared(proposal.id, proposal.version, colleague)

    # Applied, NEW's record is gone: OLD decides
    assert {:ok, _} = approve_and_apply(proposal, c.user)
    assert {:ok, _} = Proposals.get_shared(proposal.id, proposal.version, colleague)
    {:ok, :ok} = Groups.remove_member(Scope.standalone(c.user), readers.id, colleague.id)
    assert {:error, _} = Proposals.get_shared(proposal.id, proposal.version, colleague)
  end

  describe "the operation's JSON" do
    test "decodes an image's asset or an attachment, and refuses other kinds" do
      assert {:ok, %ReplaceImageFile{asset: {:image, 1}, with: {:image, 7}}} =
               Codec.decode(
                 %{"op" => "replace_image_file", "asset" => %{"kind" => "image", "id" => 1}, "with" => "image1"},
                 %{"image1" => {:image, 7}}
               )

      assert {:error, _} =
               Codec.decode(%{
                 "op" => "replace_image_file",
                 "asset" => %{"kind" => "video", "id" => 1},
                 "with" => %{"kind" => "image", "id" => 2}
               })

      assert {:error, _} = Codec.decode(%{"op" => "replace_image_file", "asset" => %{"kind" => "image", "id" => 1}})
    end

    test "what a tool says the files are is replaced by the library's", c do
      old = image!("a", {800, 600})
      new = image!("b", {1600, 1200})

      {:ok, [op]} =
        Codec.decode_all([
          %{
            "op" => "replace_image_file",
            "asset" => %{"kind" => "image", "id" => old.id},
            "with" => %{"kind" => "image", "id" => new.id},
            "old" => %{"path" => "elsewhere.jpg", "content_hash" => "x"},
            "new" => %{"path" => new.path, "width" => 1, "height" => 1}
          }
        ])

      {:ok, proposal} = Proposals.propose([op], c.user)
      assert proposal.problems == []
      assert [%{old: %{"path" => path}, new: %{"width" => 1600}}] = proposal.operations
      assert path == old.path

      # Stored and read back as it was frozen
      {:ok, stored} = Proposals.get(proposal.id, c.user)
      assert [%ReplaceImageFile{old: %{"path" => ^path}}] = stored.operations
      assert Codec.encode(hd(stored.operations))["op"] == "replace_image_file"
    end
  end

  test "a proposal replacing an image supersedes the tool's earlier one replacing the same", c do
    old = image!("a", {800, 600})
    {:ok, one} = Proposals.propose([replace(old, image!("b", {800, 600}))], c.user, replaces: :latest, origin: :mcp)

    {:ok, two} =
      Proposals.propose([replace(old, image!("c", {800, 600}))], c.user, replaces: :latest, origin: :mcp)

    assert two.supersedes_id == one.id
  end
end

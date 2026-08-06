defmodule Brando.Uploads.AssetOrphanTest do
  @moduledoc """
  The asset-lifecycle counterpart to `test/brando/content/orphaned_blocks_test.exs`.

  **The plan's framing for this task was wrong, and checking it first is the
  point.** Phase 4 asked for a test that "uploaded rows are cleaned up on a
  failed or reset save". They are not, deliberately: `docs/UPLOADER.md:529` makes
  asset creation independent of delivery, and `research/03-uploads.md:88` records
  the consequence as an *accepted-by-design orphan* — "the asset row is
  permanent… there is no GC for unreferenced assets". Writing a cleanup test
  would have asserted a guarantee the system never made, exactly the mistake D2
  made with delivery ACKs.

  So these tests pin the contract that actually holds, in both directions:

    * an asset survives everything the editor can do to an entry, because it is
      shared library content and deleting it would take other entries' media
      with it;
    * the *references* to an asset are what give way when the asset itself is
      purged.

  A future asset GC has to change this file on purpose, which is the same job
  `orphaned_blocks_test.exs` does for blocks.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Images.Image
  alias Brando.Pages.Page
  alias Brando.SoftDelete.Query
  alias Ecto.Changeset

  defp days_ago(days) do
    DateTime.utc_now()
    |> DateTime.add(-days * 24 * 3600, :second)
    |> DateTime.truncate(:second)
  end

  defp soft_delete(struct, days) do
    struct |> Changeset.change(%{deleted_at: days_ago(days)}) |> Brando.Repo.update!()
  end

  describe "an asset that never reaches an entry" do
    # The documented tradeoff, stated as a test. An upload creates its row before
    # anything is delivered anywhere, so abandoning the form leaves that row in
    # the library forever — retrievable through the picker, collected by nothing.
    #
    # The control row is what makes this an assertion rather than a sentence. On
    # its own, "an image with `deleted_at == nil` survives a purge" is satisfied
    # by a `clean_up_soft_deletions/0` that does nothing at all — including one
    # broken into a no-op. Purging a genuinely stale row in the same call proves
    # the collector ran and still declined to take the orphan.
    test "survives a purge that collects everything it is supposed to" do
      user = Factory.insert(:random_user)
      orphan = Factory.insert(:image, creator: user)
      stale = Factory.insert(:image, creator: user)

      soft_delete(stale, 60)
      Query.clean_up_soft_deletions()

      refute Brando.Repo.get(Image, stale.id), "the purge did not run"
      assert Brando.Repo.get(Image, orphan.id)
      assert Brando.Repo.get(Image, orphan.id).deleted_at == nil
    end

    # The save failing is not a signal to destroy the upload: the user's next
    # move is usually to fix the validation error and save again, with the same
    # image still picked.
    #
    # Driven through `Page.changeset/5` rather than a `validate_required/2` the
    # test bolts on. The earlier version invented its own failing changeset, so
    # it asserted only that Ecto does not delete unrelated rows when an insert
    # fails — true of any schema in any application, and unable to go red for
    # anything in this repo. `uri` is `required: true` on the blueprint
    # (`page.ex:94`), so this is the validation a user actually hits.
    test "survives a failed entry save" do
      user = Factory.insert(:random_user)
      image = Factory.insert(:image, creator: user)

      {:error, changeset} =
        %Page{}
        |> Page.changeset(
          %{
            title: "No uri",
            template: "default.html",
            language: "en",
            status: :published,
            meta_image_id: image.id
          },
          user
        )
        |> Brando.Repo.insert()

      # Pin the premise: the save failed for the reason the test claims — the
      # missing `uri` and nothing else — and the entry really was carrying the
      # image when it did. Asserting the whole error list rather than `:uri in`
      # it matters: `language` and `status` are required too, so a weaker
      # assertion passes while the test is failing for a reason it never names.
      assert Keyword.keys(changeset.errors) == [:uri]
      assert Changeset.get_field(changeset, :meta_image_id) == image.id

      assert Brando.Repo.get(Image, image.id)
    end
  end

  describe "detaching an asset from an entry" do
    # What `Form.handle_event("reset_image_field", …)` does is nil the FK and
    # nothing else. This asserts why that is right rather than lazy: the same
    # image row is shared, so deleting it would blank a field on every other
    # entry that picked it.
    test "clearing the field drops the reference and leaves the row and its other users alone" do
      user = Factory.insert(:random_user)
      image = Factory.insert(:image, creator: user)
      page = Factory.insert(:page, creator: user, meta_image_id: image.id)
      sibling = Factory.insert(:page, creator: user, meta_image_id: image.id)

      page |> Changeset.change(%{meta_image_id: nil}) |> Brando.Repo.update!()

      assert Brando.Repo.get(Page, page.id).meta_image_id == nil
      assert Brando.Repo.get(Page, sibling.id).meta_image_id == image.id
      assert Brando.Repo.get(Image, image.id)
    end

    # Deleting the entry is the strongest form of "detach", and it is still not a
    # reason to destroy library content.
    test "deleting the entry leaves the asset in the library" do
      user = Factory.insert(:random_user)
      image = Factory.insert(:image, creator: user)
      page = Factory.insert(:page, creator: user, meta_image_id: image.id)

      Brando.Repo.delete!(page)

      assert Brando.Repo.get(Image, image.id)
    end
  end

  describe "purging an asset that entries still reference" do
    # The one direction that *is* destructive, and the only real GC in the tree:
    # `clean_up_soft_deletions/0` hard-deletes rows soft-deleted more than 30
    # days ago. Every asset FK is `on_delete: :nilify_all`, so the entries lose
    # the reference and survive — a page whose meta image was purged still
    # renders.
    test "nilifies the referencing entries rather than failing" do
      user = Factory.insert(:random_user)
      image = Factory.insert(:image, creator: user)
      page = Factory.insert(:page, creator: user, meta_image_id: image.id)

      soft_delete(image, 60)
      Query.clean_up_soft_deletions()

      refute Brando.Repo.get(Image, image.id)
      assert Brando.Repo.get(Page, page.id).meta_image_id == nil
    end

    # The regression this guards is a whole-job failure, not a single row's.
    # `clean_up_soft_deletions/0` maps over every soft-delete schema in turn, so
    # one FK without `on_delete` raises `foreign_key_violation` and every schema
    # after it in the list is never purged. Verified against the fixtures before
    # `20260806000000_nilify_asset_fks_in_test_schemas` corrected them: the purge
    # raised on `pages_meta_image_id_fkey`.
    test "a referenced asset does not wedge the purge for other schemas" do
      user = Factory.insert(:random_user)
      image = Factory.insert(:image, creator: user)
      _referencing_page = Factory.insert(:page, creator: user, meta_image_id: image.id)
      stale_page = Factory.insert(:page, creator: user)

      soft_delete(image, 60)
      soft_delete(stale_page, 60)

      Query.clean_up_soft_deletions()

      refute Brando.Repo.get(Image, image.id)
      refute Brando.Repo.get(Page, stale_page.id), "the purge stopped before reaching pages"
    end

    # Inside the window, nothing is touched — a soft delete is undoable until it
    # is not, and an asset removed by mistake has 30 days to come back.
    test "leaves a recently soft-deleted asset and its references intact" do
      user = Factory.insert(:random_user)
      image = Factory.insert(:image, creator: user)
      page = Factory.insert(:page, creator: user, meta_image_id: image.id)

      soft_delete(image, 1)
      Query.clean_up_soft_deletions()

      assert Brando.Repo.get(Image, image.id)
      assert Brando.Repo.get(Page, page.id).meta_image_id == image.id
    end
  end

  describe "gallery objects" do
    # Gallery objects are join rows with no life of their own, so unlike assets
    # they *must* be collected — `on_delete: :delete_all` on both FKs. Deleting
    # the gallery takes them; purging an image takes only the rows that pointed
    # at it.
    test "are deleted with their gallery" do
      user = Factory.insert(:random_user)
      image = Factory.insert(:image, creator: user)

      gallery =
        Factory.insert(:gallery,
          gallery_objects: [Factory.build(:gallery_object, image: image, creator: user)]
        )

      [object] = Brando.Repo.preload(gallery, :gallery_objects).gallery_objects

      Brando.Repo.delete!(gallery)

      refute Brando.Repo.get(Brando.Galleries.GalleryObject, object.id)
      assert Brando.Repo.get(Image, image.id), "the image is library content, not the gallery's"
    end

    test "are deleted when the image they hold is purged" do
      user = Factory.insert(:random_user)
      image = Factory.insert(:image, creator: user)

      gallery =
        Factory.insert(:gallery,
          gallery_objects: [Factory.build(:gallery_object, image: image, creator: user)]
        )

      [object] = Brando.Repo.preload(gallery, :gallery_objects).gallery_objects

      soft_delete(image, 60)
      Query.clean_up_soft_deletions()

      refute Brando.Repo.get(Brando.Galleries.GalleryObject, object.id)
      assert Brando.Repo.get(Brando.Galleries.Gallery, gallery.id)
    end
  end
end

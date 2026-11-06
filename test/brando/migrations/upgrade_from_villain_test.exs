defmodule Brando.Migrations.UpgradeFromVillainTest do
  # A pre-blocks site taken through every later upgrade template
  # (Brando.UpgradeFromVillainCase, which has the setup and helpers):
  # its content, and its legacy media and multi module code.
  use Brando.UpgradeFromVillainCase

  alias Brando.Migration.LegacyConversion
  alias Mix.Tasks.Brando.Repair.LegacyMedia, as: RepairTask

  test "a pre-blocks site's Villain content comes through brando_103 onwards" do
    load_schema()
    %{page: page_id, fragment: fragment_id} = insert_villain_site()

    Enum.each(templates(103..1000), &migrate/1)

    blocks =
      rows(
        """
        SELECT b.id, b.type, b.multi, b.fragment_id FROM content_blocks b
        JOIN pages_blocks pb ON pb.block_id = b.id
        WHERE pb.entry_id = $1 ORDER BY pb.sequence
        """,
        [page_id]
      )

    assert [
             [_, "fragment", false, ^fragment_id],
             [_, "fragment", false, nil],
             [multi_block, "module", true, nil],
             [video_block, "module", false, nil],
             [other_video_block, "module", false, nil]
           ] = blocks

    # The multi module's own var, above its entries
    assert rows("SELECT key, value FROM content_vars WHERE block_id = $1", [multi_block]) == [["heading", "Our values"]]

    assert rows(
             """
             SELECT v.value FROM content_vars v JOIN content_blocks b ON v.block_id = b.id
             WHERE b.parent_id = $1 ORDER BY b.sequence
             """,
             [multi_block]
           ) == [["Value 1"], ["Value 2"]]

    # Pre-0.54 Brando always rendered file videos with `loop`, and drew its SVG
    # placeholder for any file video with a width, whatever `cover` held
    assert rows(
             """
             SELECT name, data->'data'->'loop', data->'data'->>'cover' FROM content_refs
             WHERE block_id = $1 ORDER BY name
             """,
             [video_block]
           ) == [["cover_video", true, "svg"], ["video", true, "svg"]]

    # The placeholder needed the block's width; embeds never had one
    assert rows(
             "SELECT name, data->'data'->>'cover' FROM content_refs WHERE block_id = $1 ORDER BY name",
             [other_video_block]
           ) == [
             ["autoplaying", "svg"],
             ["scaled", "svg"],
             ["unsized", "false"],
             ["video", "svg"],
             ["vimeo", "false"],
             ["with_button", "svg"],
             ["youtube", "false"]
           ]

    # Blocks had no `muted`. Brando before 0.53 muted every file video, and a
    # file video only the site's script starts must be muted to play; one with
    # a play button or controls keeps its sound, and autoplay always mutes
    assert rows(
             "SELECT name, data->'data'->'muted' FROM content_refs WHERE block_id IN ($1, $2) ORDER BY block_id, name",
             [video_block, other_video_block]
           ) == [
             ["cover_video", true],
             ["video", true],
             ["autoplaying", true],
             ["scaled", true],
             ["unsized", true],
             ["video", true],
             ["vimeo", false],
             ["with_button", false],
             ["youtube", false]
           ]

    # One video record per file, sized by the first block that used it; a
    # block that drew it in another shape keeps that shape as its own
    # aspect ratio
    assert rows(
             """
             SELECT r.name, v.type, v.source_url, v.width, v.height, r.data->'data'->>'aspect_ratio'
             FROM content_refs r JOIN videos v ON v.id = r.video_id
             WHERE r.block_id IN ($1, $2) ORDER BY r.block_id, r.name
             """,
             [video_block, other_video_block]
           ) == [
             ["cover_video", "external_file", "https://cdn.example.com/video.mp4", 840, 1052, nil],
             ["video", "external_file", "https://cdn.example.com/video.mp4", 840, 1052, nil],
             ["autoplaying", "external_file", "https://cdn.example.com/video.mp4", 840, 1052, nil],
             # The same shape at another scale (971×1216 against 840×1052)
             ["scaled", "external_file", "https://cdn.example.com/video.mp4", 840, 1052, nil],
             ["unsized", "external_file", "https://cdn.example.com/video.mp4", 840, 1052, nil],
             ["video", "external_file", "https://cdn.example.com/video.mp4", 840, 1052, "400:300"],
             ["vimeo", "vimeo", "https://vimeo.com/76979871", 640, 360, nil],
             ["with_button", "external_file", "https://cdn.example.com/video.mp4", 840, 1052, nil],
             ["youtube", "youtube", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", 840, 1052, nil]
           ]
  end

  describe "legacy media and multi module code (koi)" do
    test "brando_133 makes images of picture and gallery data that matches no row" do
      load_schema()
      insert_villain_site()
      %{page: page_id, images: images} = insert_koi_page()

      Enum.each(templates(103..1000), &migrate/1)

      assert [
               ["pic", "images/site/posts/1n60vo3o9p06.jpg", false, nil],
               # A new row, not the one in the trash: that one is purged with
               # everything linked to it
               ["pic2", "images/site/posts/trashed.jpg", false, nil],
               ["pic3", "images/site/posts/by-size.png", false, nil],
               ["pic4", nil, false, nil],
               ["pic5", "images/site/posts/linked.jpg", false, nil],
               ["gallery", nil, false, gallery_id],
               ["media", nil, false, nil],
               ["content", "images/site/posts/hero.jpg", false, nil]
             ] = ref_media(page_id)

      assert [["images/site/posts/1n60vo3o9p06.jpg", sizes, 1600, 1067, "#9a8f7e", ["jpg"]]] =
               rows(
                 "SELECT path, sizes, width, height, dominant_color, formats FROM images WHERE path LIKE '%1n60vo3o9p06%'"
               )

      assert sizes["small"] == "images/site/posts/small/1n60vo3o9p06.jpg"

      [[trashed_rows]] = rows("SELECT count(*) FROM images WHERE path = 'images/site/posts/trashed.jpg'")
      assert trashed_rows == 2
      assert [[_]] = rows("SELECT id FROM images WHERE id = $1 AND deleted_at IS NOT NULL", [images.deleted])

      assert gallery_images(gallery_id) == [
               ["images/site/gallery/known.jpg", %{"title" => "Known"}],
               ["images/site/gallery/lost.jpg", %{"alt" => "Lost"}]
             ]

      # The ref keeps its own texts; the image data is on the image now
      assert [[%{"title" => "Jobb med oss", "alt" => "Verkstedet"} = data]] =
               rows(
                 "SELECT r.data->'data' FROM content_refs r JOIN pages_blocks pb ON pb.block_id = r.block_id WHERE pb.entry_id = $1 AND r.name = 'pic'",
                 [page_id]
               )

      refute Map.has_key?(data, "path")

      assert {:ok, %{findings: []}} = LegacyConversion.check("public")
    end

    test "the check names the media the shipped brando_133 lost" do
      load_schema()
      insert_villain_site()
      %{page: page_id, koi_path: koi_path} = insert_koi_page()

      migrate_with_shipped_133()

      at = ~s|pages ##{page_id} › block 1 (module "Jobb med oss")|
      since = "(lost in the conversion, or removed by an editor since)"

      expected = [
        "#{at} › ref pic: legacy image #{koi_path} has no image now #{since}",
        "#{at} › ref pic2: legacy image images/site/posts/trashed.jpg has no image now #{since}",
        "#{at} › ref pic3: legacy image images/site/posts/stale.jpg has no image now #{since}",
        "#{at} › ref gallery: 2 legacy images, 1 in its gallery now #{since}",
        "pages ##{page_id} › block 3 (picture, wrapped) › ref content: legacy image /media/images/site/posts/hero.jpg has no image now #{since}"
      ]

      assert findings() == Enum.map(expected, &{:missing, &1})

      assert {{:exit, {:shutdown, 1}}, output} = run_check([])
      assert Enum.map(expected, &("  " <> &1)) -- output == []
      assert last_line(output) =~ "5 missing"
    end

    test "the repair task puts back what the shipped brando_133 lost, after a dry run that writes nothing" do
      load_schema()
      insert_villain_site()
      %{page: page_id, images: images} = insert_koi_page()

      migrate_with_shipped_133()

      state = fn ->
        {ref_media(page_id), rows("SELECT id, path, deleted_at FROM images ORDER BY id"),
         rows("SELECT id, gallery_id, image_id, sequence, config FROM galleries_gallery_objects ORDER BY id")}
      end

      before = state.()
      at = ~s|pages ##{page_id} › block 1 (module "Jobb med oss")|

      assert {nil, ["Repairing legacy media in public (dry run: nothing is written)\n", "Changes after " <> _ | output]} =
               run_task(RepairTask, ["--dry-run"])

      assert [
               "  #{at} › ref pic › makes an image of images/site/posts/1n60vo3o9p06.jpg from the legacy data and links it",
               "  #{at} › ref pic2 › makes an image of images/site/posts/trashed.jpg from the legacy data and links it",
               "  #{at} › ref pic3 › links image ##{images.by_size} (images/site/posts/by-size.png)",
               "  #{at} › ref gallery › adds 1 image to gallery #1 (1 made from the legacy data)",
               "  pages ##{page_id} › block 3 (picture, wrapped) › ref content › makes an image of images/site/posts/hero.jpg from the legacy data and links it"
             ] == Enum.slice(output, 0, 5)

      assert summary_line(output) =~ "5 refs to repair: 4 images and 0 videos to make from the legacy data."
      assert last_line(output) == "Run without --dry-run to write them, then mix brando.entries.resave."
      assert state.() == before
      assert length(findings()) == 5

      assert {nil, output} = run_task(RepairTask, [])
      assert summary_line(output) =~ "5 refs repaired: 4 images and 0 videos made from the legacy data."
      assert last_line(output) == "Run mix brando.entries.resave, and restart a running server."

      assert findings() == []

      assert [
               ["pic", "images/site/posts/1n60vo3o9p06.jpg", false, nil],
               ["pic2", "images/site/posts/trashed.jpg", false, nil],
               ["pic3", "images/site/posts/by-size.png", false, nil],
               ["pic4", nil, false, nil],
               ["pic5", "images/site/posts/linked.jpg", false, nil],
               ["gallery", nil, false, gallery_id],
               ["media", nil, false, nil],
               ["content", "images/site/posts/hero.jpg", false, nil]
             ] = ref_media(page_id)

      assert [["images/site/posts/1n60vo3o9p06.jpg", sizes, 1600, 1067, "#9a8f7e", ["jpg"]]] =
               rows(
                 "SELECT path, sizes, width, height, dominant_color, formats FROM images WHERE path LIKE '%1n60vo3o9p06%'"
               )

      assert sizes["small"] == "images/site/posts/small/1n60vo3o9p06.jpg"

      assert gallery_images(gallery_id) == [
               ["images/site/gallery/known.jpg", %{"title" => "Known"}],
               ["images/site/gallery/lost.jpg", %{"alt" => "Lost"}]
             ]

      assert [[0], [1]] =
               rows("SELECT sequence FROM galleries_gallery_objects WHERE gallery_id = $1 ORDER BY sequence", [gallery_id])

      # Nothing left to do
      repaired = state.()
      assert {nil, ["No media to repair in public."]} = run_task(RepairTask, [])
      assert state.() == repaired

      assert {nil, output} = run_check([])
      assert last_line(output) =~ "every Villain block, var, ref and fragment came through"
    end

    test "the repair task stops when the Villain columns are gone" do
      load_schema()
      insert_villain_site()
      insert_koi_page()
      migrate_with_shipped_133()

      for table <- ~w(pages pages_fragments content_templates), do: rows("ALTER TABLE #{table} DROP COLUMN data")

      assert {nil, [message]} = run_task(RepairTask, [])
      assert message =~ "No Villain column left in public: there is no legacy data to repair from."

      assert message =~
               "Not repaired, the Villain column is gone: content_templates.data, pages.data, pages_fragments.data."
    end

    test "brando_219 rewrites the services module to read its entries' vars" do
      load_schema()
      insert_villain_site()
      %{services: services_id} = insert_koi_page()

      Enum.each(templates(103..1000), &migrate/1)

      assert [[code]] = rows("SELECT code FROM content_modules WHERE id = $1", [services_id])

      assert code == """
             {% assign first_entry = entries.first %}<p>{{ first_entry.vars.text }}</p>
             {% for link in entries %}<a href="{{ link.vars.url }}">{{ link.vars.text }}</a>{% endfor %}
             {{ content | renderless }}
             """
    end
  end
end

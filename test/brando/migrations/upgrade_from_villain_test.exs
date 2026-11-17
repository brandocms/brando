defmodule Brando.Migrations.UpgradeFromVillainTest do
  # A pre-blocks site taken through every later upgrade template
  # (Brando.UpgradeFromVillainCase, which has the setup and helpers):
  # its content, and its legacy media and multi module code.
  use Brando.UpgradeFromVillainCase

  alias Brando.Migration.LegacyConversion
  alias Brando.Utils
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

  # Content a 0.51 production dump had, replayed through the chain
  describe "0.51 content" do
    test "brando_108 keeps html, svg, map and comment blocks as refs of their own type" do
      load_schema()
      insert_villain_site()

      blocks = [
        %{
          "type" => "html",
          "uid" => Utils.generate_uid(),
          "hidden" => false,
          "data" => %{"text" => ~s(<ul><li><a href="{{ links.facebook.url }}">Facebook</a></li></ul>)}
        },
        %{
          "type" => "svg",
          "uid" => Utils.generate_uid(),
          "hidden" => false,
          "data" => %{"code" => ~s(<svg viewBox="0 0 1 1"></svg>), "class" => "logo"}
        },
        %{
          "type" => "map",
          "uid" => Utils.generate_uid(),
          "hidden" => false,
          "data" => %{
            "embed_url" => "//www.google.com/maps/embed?pb=!1m18",
            "source" => "gmaps",
            "class" => "map"
          }
        },
        # An editor's note, which never rendered
        %{
          "type" => "comment",
          "uid" => Utils.generate_uid(),
          "hidden" => false,
          "data" => %{"text" => "Kommentar..."}
        }
      ]

      [[page_id]] =
        insert!(
          """
          INSERT INTO pages (uri, language, title, template, status, data, inserted_at, updated_at)
          VALUES ('legacy', 'en', 'Legacy', 'default.html', 1, $1, now(), now())
          """,
          [blocks]
        )

      Enum.each(templates(103..1000), &migrate/1)

      # brando_147 gives every ref of the wrapper its text editor's
      # extensions, which refs of other types do not read
      refs =
        rows(
          """
          SELECT r.data->>'type', (r.data->'data') - 'extensions' FROM content_refs r
          JOIN content_blocks b ON b.id = r.block_id
          JOIN pages_blocks pb ON pb.block_id = b.id
          WHERE pb.entry_id = $1 ORDER BY pb.sequence
          """,
          [page_id]
        )

      assert [
               ["html", html],
               ["svg", svg],
               ["map", map],
               ["comment", comment]
             ] = refs

      assert html == %{
               "text" => ~s(<ul><li><a href="{{ links.facebook.url }}">Facebook</a></li></ul>),
               "params" => [],
               "values" => %{}
             }

      assert svg == %{"code" => ~s(<svg viewBox="0 0 1 1"></svg>), "class" => "logo"}
      assert map == %{"embed_url" => "//www.google.com/maps/embed?pb=!1m18", "source" => "gmaps"}
      assert comment == %{"text" => "Kommentar..."}

      # The check knows the comment block is wrapped as well
      assert findings() == []
    end

    test "brando_108 keeps refs deleted on 0.51 inactive" do
      load_schema()
      insert_villain_site()

      [[module_id]] =
        insert!(
          """
          INSERT INTO content_modules (name, namespace, class, code, refs, vars, wrapper, inserted_at, updated_at)
          VALUES ('Heading', 'pages', 'heading', '{% ref refs.h2 %}{% ref refs.p %}{% ref refs.items %}{% ref refs.hours %}', $1, '[]', false, now(), now())
          """,
          [[text_ref("h2", "Overskrift"), text_ref("p", "Text")]]
        )

      deleted = &Map.merge(&1, %{"deleted" => true, "description" => ""})
      deleted_heading = deleted.(text_ref("h2", "Overskrift"))

      deleted_list =
        deleted.(%{
          "name" => "items",
          "data" => %{
            "type" => "list",
            "uid" => Utils.generate_uid(),
            "hidden" => false,
            "data" => %{"rows" => [%{"value" => "<p>One</p>"}, %{"value" => "<p>Two</p>"}]}
          }
        })

      deleted_table = deleted.(table_ref("hours", ["Mon", "Tue"]))

      blocks = [
        %{
          "type" => "module",
          "uid" => Utils.generate_uid(),
          "hidden" => false,
          "data" => %{
            "module_id" => module_id,
            "multi" => false,
            "refs" => [deleted_heading, text_ref("p", "Kept"), deleted_list, deleted_table],
            "vars" => []
          }
        }
      ]

      [[page_id]] =
        insert!(
          """
          INSERT INTO pages (uri, language, title, template, status, data, inserted_at, updated_at)
          VALUES ('deleted-refs', 'en', 'Deleted refs', 'default.html', 1, $1, now(), now())
          """,
          [blocks]
        )

      Enum.each(templates(103..1000), &migrate/1)

      assert rows(
               """
               SELECT r.name, r.active FROM content_refs r
               JOIN pages_blocks pb ON pb.block_id = r.block_id
               WHERE pb.entry_id = $1 ORDER BY r.name
               """,
               [page_id]
             ) == [["h2", false], ["p", true]]

      # A deleted list or table rendered nothing either: its rows are not kept
      assert rows(
               """
               SELECT count(*) FROM content_table_rows t
               JOIN pages_blocks pb ON pb.block_id = t.block_id
               WHERE pb.entry_id = $1
               """,
               [page_id]
             ) == [[0]]

      assert findings() == []
    end

    test "brando_131 gives the videos brando_95 made their type and source URL" do
      load_schema()
      insert_villain_site()

      insert_video = fn source, url, remote_id ->
        insert!(
          """
          INSERT INTO videos (source, url, remote_id, width, height, config_target, creator_id, inserted_at, updated_at)
          VALUES ($1, $2, $3, 640, 360, 'video:MyApp.Projects.Project:video', 1, now(), now())
          """,
          [source, url, remote_id]
        )
      end

      [[vimeo]] = insert_video.("vimeo", "https://vimeo.com/76979871", "76979871")
      [[vimeo_id_only]] = insert_video.("vimeo", nil, "76979872")
      [[youtube]] = insert_video.("youtube", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ")
      [[file]] = insert_video.("file", "https://cdn.example.com/film.mp4", "https://cdn.example.com/film.mp4")
      # A start time in the id, which the player's own query would follow
      [[youtube_at]] = insert_video.("youtube", nil, "abc123?start=30")
      # A field video with the file the site's video blocks play
      [[field_video]] = insert_video.("file", "https://cdn.example.com/video.mp4", nil)

      Enum.each(templates(103..1000), &migrate/1)

      # The blocks get videos of their own, without the field video's settings
      assert rows("SELECT count(*) FROM content_refs WHERE video_id = $1", [field_video]) == [[0]]
      assert [[count]] = rows("SELECT count(*) FROM content_refs WHERE video_id IS NOT NULL")
      assert count > 0

      assert rows("SELECT id, type, source_url, remote_id FROM videos WHERE id = ANY($1) ORDER BY id", [
               [vimeo, vimeo_id_only, youtube, file, youtube_at]
             ]) == [
               [vimeo, "vimeo", "https://vimeo.com/76979871", "76979871"],
               [vimeo_id_only, "vimeo", "https://vimeo.com/76979872", "76979872"],
               [youtube, "youtube", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"],
               [file, "external_file", "https://cdn.example.com/film.mp4", "https://cdn.example.com/film.mp4"],
               [youtube_at, "youtube", "https://www.youtube.com/watch?v=abc123", "abc123"]
             ]
    end

    test "brando_89 stores a datasource's integer limit as text" do
      load_schema()
      [[module_id]] = datasource_page(5)

      migrate(hd(templates(89..89)))

      assert rows(
               "SELECT v->>'key', v->'value' FROM content_modules, jsonb_array_elements(vars) v WHERE id = $1",
               [module_id]
             ) == [["limit", "5"]]
    end

    test "a limit an earlier brando_89 stored as a number still goes through brando_107 and brando_108" do
      load_schema()
      [[module_id]] = datasource_page(5)

      # brando_89 as it shipped, which kept the number
      migrate(hd(templates(89..89)), &String.replace(&1, ~s|"value" => to_string(limit)|, ~s|"value" => limit|))

      assert rows(
               "SELECT v->'value' FROM content_modules, jsonb_array_elements(vars) v WHERE id = $1",
               [module_id]
             ) == [[5]]

      Enum.each(templates(103..1000), &migrate/1)

      assert rows("SELECT module_id, block_id, value FROM content_vars WHERE key = 'limit' ORDER BY module_id NULLS LAST") ==
               [[module_id, nil, "5"], [nil, root_block_id(), "5"]]
    end
  end

  # A 0.51 page whose only block is a datasource of a module listing pages,
  # without the columns brando_89 adds
  defp datasource_page(limit) do
    insert_villain_site()

    rows(
      "ALTER TABLE content_modules DROP COLUMN datasource, DROP COLUMN datasource_module, " <>
        "DROP COLUMN datasource_type, DROP COLUMN datasource_query"
    )

    [[module_id]] =
      module =
      insert!(
        """
        INSERT INTO content_modules (name, namespace, class, code, refs, vars, wrapper, inserted_at, updated_at)
        VALUES ('Latest', 'pages', 'latest', '{% for entry in entries %}{{ entry.title }}{% endfor %}', '[]', '[]', false, now(), now())
        """,
        []
      )

    block = %{
      "type" => "datasource",
      "uid" => Utils.generate_uid(),
      "data" => %{
        "module_id" => module_id,
        "module" => "Elixir.Brando.Pages.Page",
        "type" => "list",
        "query" => "latest",
        "limit" => limit,
        "arg" => nil,
        "ids" => []
      }
    }

    insert!(
      """
      INSERT INTO pages (uri, language, title, template, status, data, inserted_at, updated_at)
      VALUES ('latest', 'en', 'Latest', 'default.html', 1, $1, now(), now())
      """,
      [[block]]
    )

    module
  end

  defp root_block_id do
    [[id]] = rows("SELECT pb.block_id FROM pages_blocks pb JOIN pages p ON p.id = pb.entry_id WHERE p.uri = 'latest'")
    id
  end
end

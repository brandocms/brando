defmodule Brando.Migrations.UpgradeFromVillainRepairTest do
  # A pre-blocks site taken through every later upgrade template
  # (Brando.UpgradeFromVillainCase, which has the setup and helpers):
  # repairing its legacy media weeks after the conversion.
  use Brando.UpgradeFromVillainCase

  alias Brando.Utils
  alias Mix.Tasks.Brando.Repair.LegacyMedia, as: RepairTask

  describe "repairing legacy media safely, weeks after the conversion" do
    test "an entry whose blocks no longer line up with Villain's is left alone" do
      %{page: page_id, state: state} = lost_media()

      # An editor adds another "Jobb med oss" block above the one that lost
      # its pictures: by position, Villain's block 1 is the new one now
      [[jobs]] = rows("SELECT id FROM content_modules WHERE class = 'jobs'")

      [[block]] =
        insert!(
          "INSERT INTO content_blocks (uid, type, module_id, active, collapsed, inserted_at, updated_at) VALUES ($1, 'module', $2, true, false, now(), now())",
          [Utils.generate_uid(), jobs]
        )

      for name <- ~w(pic pic2 pic3 pic5) do
        rows(
          "INSERT INTO content_refs (uid, name, block_id, data, sequence, active, collapsed, inserted_at, updated_at) VALUES ($1, $2, $3, $4, 0, true, false, now(), now())",
          [Utils.generate_uid(), name, block, %{"type" => "picture", "data" => %{}}]
        )
      end

      rows("UPDATE pages_blocks SET sequence = sequence + 1 WHERE entry_id = $1", [page_id])
      rows("INSERT INTO pages_blocks (entry_id, block_id, sequence) VALUES ($1, $2, 0)", [page_id, block])

      before = state.()
      assert [_ | _] = repairs = repairs()

      for {_ref, action} <- repairs do
        assert {:skip, "3 blocks in Villain, 4 now"} = action
      end

      assert {nil, _output} = run_task(RepairTask, [])
      assert state.() == before
    end

    test "a wrapped block in another module, or a ref of another type now, is left alone" do
      %{page: page_id, state: state} = lost_media()

      wrapper = root_block(page_id, 2)
      rows("UPDATE content_refs SET data = jsonb_set(data, '{type}', '\"text\"') WHERE block_id = $1", [wrapper])
      before = state.()

      assert Enum.all?(
               repairs(),
               &match?({_, {:skip, "block 3 › a picture block in Villain, its content ref is not a picture now"}}, &1)
             )

      run_task(RepairTask, [])
      assert state.() == before

      [[jobs]] = rows("SELECT id FROM content_modules WHERE class = 'jobs'")
      rows("UPDATE content_blocks SET module_id = $1 WHERE id = $2", [jobs, wrapper])

      assert Enum.all?(
               repairs(),
               &match?({_, {:skip, "block 3 › a picture block in Villain, now not in a Legacy Content Wrapper"}}, &1)
             )
    end

    test "an entry, block or gallery edited since the conversion is left alone" do
      %{page: page_id, state: state} = lost_media()
      before = state.()

      # An editor cleared a picture, or removed gallery images: the entry's
      # save moves its edited_at
      rows("UPDATE pages SET edited_at = $1 WHERE id = $2", [utc_in(60), page_id])
      assert Enum.all?(repairs(), &match?({_, {:skip, "edited " <> _}}, &1))
      run_task(RepairTask, [])
      assert state.() == before

      rows("UPDATE pages SET edited_at = NULL WHERE id = $1", [page_id])
      rows("UPDATE content_blocks SET edited_at = $1 WHERE id = $2", [utc_in(86_400), root_block(page_id, 2)])
      [[gallery_id]] = rows("SELECT gallery_id FROM content_refs WHERE name = 'gallery' AND gallery_id IS NOT NULL")
      rows("UPDATE galleries_gallery_objects SET edited_at = $1 WHERE gallery_id = $2", [utc_in(86_400), gallery_id])

      assert %{
               "ref content" => {:skip, "its block was edited since the conversion"},
               "ref gallery" => {:skip, "its gallery was edited since the conversion"},
               "ref pic" => {:make_image, _}
             } =
               Map.new(repairs())
    end

    test "rows the conversion wrote in brando_175's second are not edits" do
      %{page: page_id} = lost_media()

      # brando_175's time is cut to the second; a NOW() brando_133 or
      # brando_134 took in that second is rounded up to the next one
      [[converted_at]] = rows("SELECT inserted_at FROM schema_migrations WHERE version = $1", [version() + 175])
      rounded = NaiveDateTime.add(converted_at, 1)
      [[gallery_id]] = rows("SELECT gallery_id FROM content_refs WHERE name = 'gallery' AND gallery_id IS NOT NULL")
      rows("UPDATE galleries SET updated_at = $1 WHERE id = $2", [rounded, gallery_id])

      rows(
        "UPDATE galleries_gallery_objects SET inserted_at = $1, updated_at = $1, edited_at = $1 WHERE gallery_id = $2",
        [rounded, gallery_id]
      )

      rows("UPDATE content_blocks SET edited_at = $1 WHERE id = $2", [rounded, root_block(page_id, 2)])

      assert %{"ref gallery" => {:gallery, _}, "ref content" => {:make_image, _}} = Map.new(repairs())
    end

    test "the cutoff takes the session time zone's offset at the conversion, not at the repair" do
      %{page: page_id} = lost_media()

      # The conversion ten days ago, in daylight-saving time (+2), and the
      # repair today in standard time (+1): a zone of that shape, whatever
      # today's date. Its rule numbers days from 0 on 1 January.
      today = Date.utc_today()
      day = fn date -> Date.day_of_year(date) - 1 end
      zone = "AAA-1BBB,#{day.(Date.add(today, -20))}/0,#{day.(Date.add(today, -5))}/0"
      days = 10

      [[migrated_at]] = rows("SELECT inserted_at FROM schema_migrations WHERE version = $1", [version() + 175])
      converted_at = NaiveDateTime.add(migrated_at, -days * 86_400)
      [[gallery_id]] = rows("SELECT gallery_id FROM content_refs WHERE name = 'gallery' AND gallery_id IS NOT NULL")

      # The site as it was ten days ago
      for [table, column] <-
            rows("""
            SELECT table_name, column_name FROM information_schema.columns
            WHERE table_schema = 'public' AND data_type = 'timestamp without time zone'
              AND column_name IN ('inserted_at', 'updated_at', 'edited_at')
            """),
          do: rows(~s|UPDATE "#{table}" SET "#{column}" = "#{column}" - interval '#{days} days'|)

      BrandoIntegration.Repo.transaction(fn ->
        rows("SET LOCAL TIME ZONE '#{zone}'")
        # What `NOW()` gave the conversion's rows in that zone
        [[local, offset_now]] =
          rows(
            "SELECT ($1::timestamp AT TIME ZONE 'utc')::timestamp, extract(epoch FROM now()::timestamp - (now() AT TIME ZONE 'utc'))::integer",
            [converted_at]
          )

        assert {NaiveDateTime.diff(local, converted_at), offset_now} == {7200, 3600}
        rows("UPDATE galleries SET updated_at = $1 WHERE id = $2", [local, gallery_id])

        rows(
          "UPDATE galleries_gallery_objects SET inserted_at = $1, updated_at = $1, edited_at = $1 WHERE gallery_id = $2",
          [local, gallery_id]
        )

        rows("UPDATE content_blocks SET edited_at = $1 WHERE id = $2", [local, root_block(page_id, 2)])

        assert %{"ref gallery" => {:gallery, _}} = Map.new(repairs(converted_at: converted_at))
      end)
    end

    test "the cutoff takes the larger offset when daylight-saving time ended between brando_133 and brando_175" do
      %{page: page_id} = lost_media()

      # Daylight-saving time (+2) ends at local midnight starting today - 5,
      # 22:00 UTC the day before: brando_133 ran 20 minutes before, and
      # brando_175 20 minutes after, in standard time (+1)
      today = Date.utc_today()
      day = fn date -> Date.day_of_year(date) - 1 end
      zone = "AAA-1BBB,#{day.(Date.add(today, -20))}/0,#{day.(Date.add(today, -5))}/0"
      change = NaiveDateTime.new!(Date.add(today, -6), ~T[22:00:00])
      t133 = NaiveDateTime.add(change, -20 * 60)
      t175 = NaiveDateTime.add(change, 20 * 60)

      [[migrated_at]] = rows("SELECT inserted_at FROM schema_migrations WHERE version = $1", [version() + 175])
      seconds = NaiveDateTime.diff(migrated_at, t175)
      [[gallery_id]] = rows("SELECT gallery_id FROM content_refs WHERE name = 'gallery' AND gallery_id IS NOT NULL")

      # The site as it was then
      for [table, column] <-
            rows("""
            SELECT table_name, column_name FROM information_schema.columns
            WHERE table_schema = 'public' AND data_type = 'timestamp without time zone'
              AND column_name IN ('inserted_at', 'updated_at', 'edited_at')
            """),
          do: rows(~s|UPDATE "#{table}" SET "#{column}" = "#{column}" - interval '#{seconds} seconds'|)

      rows("UPDATE schema_migrations SET inserted_at = $1 WHERE version = $2", [t133, version() + 133])
      rows("UPDATE schema_migrations SET inserted_at = $1 WHERE version = $2", [t175, version() + 175])

      BrandoIntegration.Repo.transaction(fn ->
        rows("SET LOCAL TIME ZONE '#{zone}'")
        # What `NOW()` gave brando_133's rows in that zone
        [[local]] = rows("SELECT ($1::timestamp AT TIME ZONE 'utc')::timestamp", [t133])
        assert NaiveDateTime.diff(local, t133) == 7200
        rows("UPDATE galleries SET updated_at = $1 WHERE id = $2", [local, gallery_id])

        rows(
          "UPDATE galleries_gallery_objects SET inserted_at = $1, updated_at = $1, edited_at = $1 WHERE gallery_id = $2",
          [local, gallery_id]
        )

        rows("UPDATE content_blocks SET edited_at = $1 WHERE id = $2", [local, root_block(page_id, 2)])

        assert %{"ref gallery" => {:gallery, _}} = Map.new(repairs())
      end)
    end

    test "an image to make is left alone once the trash may have emptied one an editor deleted since" do
      %{page: page_id, images: images, state: state} = lost_media()

      # The conversion 40 days ago. pic5 was linked; an editor trashed its
      # image, and emptying the trash 30 days later deleted it and nilled
      # the ref, with no trace left
      for {table, columns} <- [
            {"schema_migrations", ~w(inserted_at)},
            {"content_blocks", ~w(inserted_at updated_at edited_at)},
            {"galleries_gallery_objects", ~w(inserted_at updated_at edited_at)}
          ] do
        set = Enum.map_join(columns, ", ", &"#{&1} = #{&1} - interval '40 days'")
        rows("UPDATE #{table} SET #{set}")
      end

      rows("DELETE FROM images WHERE id = $1", [images.linked])
      before = state.()

      doubt =
        "the conversion is more than 30 days old, and the trash is emptied after 30 days: " <>
          "media an editor deleted since may be gone without a trace, and this could bring it back"

      assert %{"ref pic5" => {:skip, ^doubt}, "ref pic" => {:skip, ^doubt}, "ref pic3" => {:link_image, _, _}} =
               Map.new(repairs())

      run_task(RepairTask, [])

      assert [
               ["pic", nil, false, nil],
               ["pic2", nil, false, nil],
               ["pic3", "images/site/posts/by-size.png", false, nil] | _
             ] =
               ref_media(page_id)

      refute state.() == before

      # Within 30 days, an image an editor trashed is still in the trash: its
      # ref is left alone, the others made
      rows("UPDATE schema_migrations SET inserted_at = inserted_at + interval '35 days'")
      rows("UPDATE images SET deleted_at = $1 WHERE path = 'images/site/posts/trashed.jpg'", [utc_in(0)])

      assert %{"ref pic2" => {:skip, "its image went to the trash " <> _}, "ref pic" => {:make_image, _}} =
               Map.new(repairs())
    end

    test "a gallery an editor emptied in its own form is not filled again" do
      %{state: state} = lost_media()

      # The gallery form saves the gallery, not the page, and leaves no
      # object to carry a time
      [[gallery_id]] = rows("SELECT gallery_id FROM content_refs WHERE name = 'gallery' AND gallery_id IS NOT NULL")
      rows("DELETE FROM galleries_gallery_objects WHERE gallery_id = $1", [gallery_id])
      before = state.()

      assert %{"ref gallery" => {:skip, "its gallery is not what the conversion left in it" <> _}} = Map.new(repairs())
      run_task(RepairTask, [])
      assert {_, _, [], _, _} = state.()
      assert elem(state.(), 2) == elem(before, 2)
    end

    test "an entry edited between planning and writing is left alone" do
      %{page: page_id, state: state} = lost_media()
      before = state.()

      # An editor picks an image for pic, saves, clears it and saves again
      edit = fn -> rows("UPDATE pages SET edited_at = $1 WHERE id = $2", [utc_in(60), page_id]) end

      assert Enum.all?(repairs(before_write: edit), &match?({_, {:skip, "edited " <> _}}, &1))
      assert state.() == before
    end

    test "a video trashed since the conversion is not made again" do
      %{about: about} = lost_media()

      video_block = root_block(about, 3)

      [[ref_id, video_id]] =
        rows("SELECT id, video_id FROM content_refs WHERE block_id = $1 AND name = 'video'", [video_block])

      # The ref lost its video, and an editor put the video in the trash a
      # minute later. The conversion's time is brando_175's whole second in
      # schema_migrations, and the migrations after it take under a second:
      # a trash time of now can share that second, which reads as not after
      rows("UPDATE content_refs SET video_id = NULL WHERE id = $1", [ref_id])
      rows("UPDATE videos SET deleted_at = $1 WHERE id = $2", [utc_in(60), video_id])
      videos = rows("SELECT id, deleted_at FROM videos ORDER BY id")

      assert %{"ref video" => {:skip, "its video went to the trash " <> _}} = Map.new(repairs())
      run_task(RepairTask, [])
      assert rows("SELECT video_id FROM content_refs WHERE id = $1", [ref_id]) == [[nil]]
      assert rows("SELECT id, deleted_at FROM videos ORDER BY id") == videos
    end

    test "a ref's video is not one of a field, though it plays the same file" do
      %{about: about} = lost_media()

      video_block = root_block(about, 3)

      [[ref_id, video_id]] =
        rows("SELECT id, video_id FROM content_refs WHERE block_id = $1 AND name = 'video'", [video_block])

      # The ref lost its video, and the only video with its file is an
      # entry's video field's, with that field's playback settings
      rows("UPDATE content_refs SET video_id = NULL WHERE block_id = $1 AND name = 'video'", [video_block])
      rows("UPDATE videos SET config_target = 'video:MyApp.Projects.Project:cover' WHERE id = $1", [video_id])

      assert %{"ref video" => {:make_video, _url}} = Map.new(repairs())
      run_task(RepairTask, [])
      assert [[new_id]] = rows("SELECT video_id FROM content_refs WHERE id = $1", [ref_id])
      assert new_id not in [nil, video_id]
    end

    test "an image picked while the repair runs stays" do
      %{page: page_id, images: images} = lost_media()

      pick = fn ->
        rows(
          "UPDATE content_refs SET image_id = $1 WHERE name = 'pic' AND block_id = $2",
          [images.known, root_block(page_id, 0)]
        )
      end

      assert %{"ref pic" => {:skip, "media was picked for it while the repair ran"}, "ref pic2" => {:make_image, _}} =
               Map.new(repairs(before_write: pick))

      assert [["pic", "images/site/gallery/known.jpg", false, nil] | _] = ref_media(page_id)
    end

    test "without the conversion's time nothing is written, and --converted-at gives it", %{copies: copies} do
      %{state: state} = lost_media()
      before = state.()
      [[migrated_at]] = rows("SELECT max(inserted_at) FROM schema_migrations")
      File.rm!(Path.join(copies, "#{version() + 133}_brando_133_transfer_ref_media_data.exs"))

      assert Enum.all?(repairs(), &match?({_, {:skip, "can't tell when brando_133 ran" <> _}}, &1))
      run_task(RepairTask, [])
      assert state.() == before

      assert {nil, output} = run_task(RepairTask, ["--converted-at", NaiveDateTime.to_iso8601(migrated_at)])
      assert Enum.any?(output, &(&1 =~ "count as editors'"))
      assert findings() == []
    end
  end
end

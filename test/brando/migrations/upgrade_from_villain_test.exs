defmodule Brando.Migrations.UpgradeFromVillainTest do
  # A database as a pre-blocks 0.53 site leaves it, with its content still
  # Villain JSON in `pages.data` and its newest Brando migration brando_102,
  # taken through every later upgrade template in order, as `mix brando.migrate`
  # does on the site.
  #
  # The chain runs in a database of its own, created for this test and dropped
  # afterwards. The templates read `information_schema` for `public` and create
  # and drop tables across it, so a sandboxed copy of the test database, which
  # already has today's tables, cannot stand in for the old one.
  use ExUnit.Case, async: false

  alias Brando.Migration.LegacyConversion
  alias Brando.Utils
  alias BrandoIntegration.Repo
  alias Mix.Tasks.Brando.Check.LegacyConversion, as: CheckTask

  @moduletag timeout: :timer.minutes(5)

  @schema "test/fixtures/upgrade/brando_102_schema.sql"
  @templates Application.app_dir(:brando, "priv/templates/brando.upgrade/migrations")

  setup do
    config = Repo.config()
    database = "#{config[:database]}_villain_#{Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)}"
    storage = Keyword.put(config, :database, database)

    :ok = Ecto.Adapters.Postgres.storage_up(storage)

    # The test repo's own connection settings (parsed from its url, which CI
    # gives credentials in), pointed at the new database and out of the sandbox
    repo_config =
      config
      |> Keyword.drop([:ownership_pool, :pool_size, :pool_overflow])
      |> Keyword.merge(
        name: nil,
        url: nil,
        database: database,
        pool: DBConnection.ConnectionPool,
        pool_size: 2,
        log: false
      )

    repo = start_supervised!({Repo, repo_config})

    Repo.put_dynamic_repo(repo)

    # Templates that walk the site's Blueprints (`Brando.Blueprint.list_blueprints/0`)
    # would find the test app's, whose tables this database never had. The
    # Villain content here lives in Brando's own tables, which the templates
    # find through `information_schema`.
    otp_app = Application.get_env(:brando, :otp_app)
    Application.put_env(:brando, :otp_app, :eex)

    on_exit(fn ->
      Application.put_env(:brando, :otp_app, otp_app)
      :ok = Ecto.Adapters.Postgres.storage_down(storage)
    end)

    :ok
  end

  defp templates(range) do
    @templates
    |> Path.join("brando_*.exs")
    |> Path.wildcard()
    |> Enum.map(&{number(&1), &1})
    |> Enum.filter(fn {number, _} -> number in range end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  defp number(path) do
    [_, number] = Regex.run(~r/brando_(\d+)_/, Path.basename(path))
    String.to_integer(number)
  end

  # `edit` changes the template's source before it is compiled
  defp migrate(path, edit \\ & &1) do
    [{module, _bytecode}] = path |> File.read!() |> edit.() |> Code.compile_string(path)

    try do
      :ok = Ecto.Migrator.up(Repo, System.unique_integer([:positive]), module, log: false)
    rescue
      error -> reraise RuntimeError, "#{Path.basename(path)}: #{Exception.message(error)}", __STACKTRACE__
    after
      :code.purge(module)
      :code.delete(module)
    end
  end

  # pg_dump output, one statement at a time; a `;` inside a function body
  # (between `$$`) does not end one
  defp load_schema do
    @schema
    |> File.read!()
    |> String.split(~r/;\n/)
    |> Enum.reduce([], fn
      part, [open | done] = statements ->
        if odd_dollar_quotes?(open), do: [open <> ";\n" <> part | done], else: [part | statements]

      part, [] ->
        [part]
    end)
    |> Enum.reverse()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or (String.starts_with?(&1, "--") and not String.contains?(&1, "\n"))))
    |> Enum.each(&Repo.query!/1)
  end

  defp odd_dollar_quotes?(sql), do: sql |> String.split("$$") |> length() |> rem(2) == 0

  defp rows(sql, params \\ []), do: Repo.query!(sql, params).rows

  defp insert!(sql, params), do: [[_id]] = rows(sql <> " RETURNING id", params)

  defp villain_video(name, extra \\ %{}) do
    %{
      "name" => name,
      "data" => %{
        "type" => "video",
        "uid" => Utils.generate_uid(),
        "hidden" => false,
        "data" =>
          Map.merge(
            %{
              "source" => "file",
              "remote_id" => "https://cdn.example.com/video.mp4",
              "cover" => "false",
              "width" => 840,
              "height" => 1052,
              "opacity" => 0,
              "preload" => true,
              "autoplay" => false,
              "controls" => false,
              "play_button" => false
            },
            extra
          )
      }
    }
  end

  defp text_ref(name, text) do
    %{
      "name" => name,
      "data" => %{
        "type" => "text",
        "uid" => Utils.generate_uid(),
        "hidden" => false,
        "data" => %{"text" => text, "type" => "paragraph"}
      }
    }
  end

  defp var(key, value, type \\ "string"),
    do: %{"key" => key, "type" => type, "label" => key, "value" => value, "important" => true}

  defp table_ref(name, cells) do
    %{
      "name" => name,
      "data" => %{
        "type" => "table",
        "uid" => Utils.generate_uid(),
        "hidden" => false,
        "data" => %{"rows" => Enum.map(cells, &%{"cols" => [var("cell", &1)]})}
      }
    }
  end

  # Content as a 0.53.0-dev site's editor saved it: a fragment block, a multi
  # module whose own vars sit above its entries, and a module with two file
  # videos, saved before blocks had a `loop` setting, one of them with a
  # Vimeo thumbnail URL in `cover`. A second page has a container holding a
  # free-standing text block and a module with a table ref, then a
  # free-standing header.
  defp insert_villain_site do
    now = ~N[2023-11-01 12:00:00]

    rows(
      "INSERT INTO users (id, name, email, inserted_at, updated_at) VALUES (1, 'Admin', 'admin@example.com', $1, $1)",
      [now]
    )

    [[multi_id]] =
      insert!(
        """
        INSERT INTO content_modules (name, namespace, class, code, refs, vars, wrapper, entry_template, inserted_at, updated_at)
        VALUES ('Values', 'pages', 'values', '<h2>{{ heading }}</h2>{{ content }}', '[]', $1, true, $2, $3, $3)
        """,
        [
          [var("heading", "Our values")],
          %{
            "id" => Ecto.UUID.generate(),
            "name" => "Value",
            "namespace" => "pages",
            "class" => "value",
            "code" => "{% ref refs.p %}",
            "refs" => [text_ref("p", "Text")],
            "vars" => [var("headerContent", "Value")],
            "wrapper" => false
          },
          now
        ]
      )

    [[video_id]] =
      insert!(
        """
        INSERT INTO content_modules (name, namespace, class, code, refs, vars, wrapper, inserted_at, updated_at)
        VALUES ('Video', 'pages', 'video', '{% ref refs.video %}{% ref refs.cover_video %}', $1, '[]', false, $2, $2)
        """,
        [[villain_video("video"), villain_video("cover_video")], now]
      )

    [[fragment_id]] =
      insert!(
        """
        INSERT INTO pages_fragments (title, parent_key, key, language, data, wrapper, inserted_at, updated_at)
        VALUES ('Footer', 'shared', 'footer', 'en', '[]', '', $1, $1)
        """,
        [now]
      )

    blocks = [
      %{
        "type" => "fragment",
        "uid" => Utils.generate_uid(),
        "hidden" => false,
        "data" => %{"fragment_id" => fragment_id}
      },
      # A fragment deleted since; the block rendered nothing
      %{
        "type" => "fragment",
        "uid" => Utils.generate_uid(),
        "hidden" => false,
        "data" => %{"fragment_id" => fragment_id + 1000}
      },
      %{
        "type" => "module",
        "uid" => Utils.generate_uid(),
        "hidden" => false,
        "data" => %{
          "module_id" => multi_id,
          "multi" => true,
          "refs" => [],
          "vars" => [var("heading", "Our values")],
          "entries" =>
            for n <- 1..2 do
              %{
                "type" => "module_entry",
                "uid" => Utils.generate_uid(),
                "hidden" => false,
                "data" => %{"refs" => [text_ref("p", "Value #{n}")], "vars" => [var("headerContent", "Value #{n}")]}
              }
            end
        }
      },
      %{
        "type" => "module",
        "uid" => Utils.generate_uid(),
        "hidden" => false,
        "data" => %{
          "module_id" => video_id,
          "multi" => false,
          "refs" => [
            villain_video("video"),
            villain_video("cover_video", %{"cover" => "https://i.vimeocdn.com/video/898839635_1290.jpg"})
          ],
          "vars" => []
        }
      },
      # The same file again at another size, as a second language's page
      # might have it, and embeds saved with only their remote id
      %{
        "type" => "module",
        "uid" => Utils.generate_uid(),
        "hidden" => false,
        "data" => %{
          "module_id" => video_id,
          "multi" => false,
          "refs" => [
            villain_video("video", %{"width" => 400, "height" => 300}),
            villain_video("vimeo", %{"source" => "vimeo", "remote_id" => "76979871", "width" => 640, "height" => 360}),
            villain_video("youtube", %{"source" => "youtube", "remote_id" => "dQw4w9WgXcQ"}),
            villain_video("unsized", %{"width" => nil, "height" => nil}),
            villain_video("scaled", %{"width" => 971, "height" => 1216}),
            villain_video("with_button", %{"play_button" => true}),
            villain_video("autoplaying", %{"autoplay" => true})
          ],
          "vars" => []
        }
      }
    ]

    [[page_id]] =
      insert!(
        """
        INSERT INTO pages (uri, language, title, template, status, data, inserted_at, updated_at)
        VALUES ('about', 'en', 'About', 'default.html', 1, $1, $2, $2)
        """,
        [blocks, now]
      )

    contact = [
      %{
        "type" => "container",
        "uid" => Utils.generate_uid(),
        "hidden" => false,
        "data" => %{
          "description" => "Intro",
          "blocks" => [
            %{
              "type" => "text",
              "uid" => Utils.generate_uid(),
              "hidden" => false,
              "data" => %{"text" => "<p>Hello</p>", "type" => "paragraph"}
            },
            %{
              "type" => "module",
              "uid" => Utils.generate_uid(),
              "hidden" => false,
              "data" => %{
                "module_id" => video_id,
                "multi" => false,
                "refs" => [villain_video("video"), villain_video("cover_video"), table_ref("hours", ["Mon", "Tue"])],
                "vars" => [var("autoplay", true, "boolean")]
              }
            }
          ]
        }
      },
      %{
        "type" => "header",
        "uid" => Utils.generate_uid(),
        "hidden" => false,
        "data" => %{"text" => "Contact", "level" => 2}
      }
    ]

    [[contact_id]] =
      insert!(
        """
        INSERT INTO pages (uri, language, title, template, status, data, inserted_at, updated_at)
        VALUES ('contact', 'en', 'Contact', 'default.html', 1, $1, $2, $2)
        """,
        [contact, now]
      )

    %{page: page_id, contact: contact_id, fragment: fragment_id}
  end

  defp picture_ref(name, data) do
    %{"name" => name, "data" => %{"type" => "picture", "uid" => Utils.generate_uid(), "hidden" => false, "data" => data}}
  end

  defp legacy_sizes(dir, file, prefix \\ "") do
    Map.new(~w(micro thumb small medium large xlarge), &{&1, "#{prefix}images/site/#{dir}/#{&1}/#{file}"})
  end

  defp insert_image!(path, extra \\ "") do
    [[id]] =
      insert!(
        """
        INSERT INTO images (path, sizes, width, height, formats, config_target, status, inserted_at, updated_at#{if extra != "", do: ", deleted_at"})
        VALUES ($1, $2, 800, 600, '{jpg}', 'default', 'processed', now(), now()#{extra})
        """,
        [path, legacy_sizes(path |> Path.dirname() |> Path.basename(), Path.basename(path))]
      )

    id
  end

  # koi's Kontakt page, as 0.53 rendered it. Its "Jobb med oss" module showed
  # two pictures purely from the ref data: the images rows for them were gone.
  # Next to those, a picture whose only row is in the trash, one whose stale
  # path matches nothing but whose sizes name a row, one already empty on
  # 0.53 and one linked by path, and a gallery with an image that has a row
  # and one that has none. A services module reads its entries the Villain
  # way, `link.data.vars.url`.
  defp insert_koi_page do
    now = ~N[2023-11-01 12:00:00]

    images = %{
      linked: insert_image!("images/site/posts/linked.jpg"),
      deleted: insert_image!("images/site/posts/trashed.jpg", ", now()"),
      by_size: insert_image!("images/site/posts/by-size.png"),
      known: insert_image!("images/site/gallery/known.jpg")
    }

    [[jobs_id]] =
      insert!(
        """
        INSERT INTO content_modules (name, namespace, class, code, refs, vars, wrapper, inserted_at, updated_at)
        VALUES ('Jobb med oss', 'pages', 'jobs', $1, $2, '[]', false, $3, $3)
        """,
        [
          Enum.map_join(~w(pic pic2 pic3 pic4 pic5 gallery), &"{% ref refs.#{&1} %}"),
          Enum.map(~w(pic pic2 pic3 pic4 pic5), &picture_ref(&1, %{})),
          now
        ]
      )

    [[services_id]] =
      insert!(
        """
        INSERT INTO content_modules (name, namespace, class, code, refs, vars, wrapper, entry_template, inserted_at, updated_at)
        VALUES ('Tjenester', 'pages', 'services', $1, '[]', '[]', true, $2, $3, $3)
        """,
        [
          """
          {% assign first_entry = entries.first %}<p>{{ first_entry.data.vars.text }}</p>
          {% for link in entries %}<a href="{{ link.data.vars.url }}">{{ link.data.vars.text }}</a>{% endfor %}
          {{ content | renderless }}
          """,
          %{
            "id" => Ecto.UUID.generate(),
            "name" => "Tjeneste",
            "namespace" => "pages",
            "class" => "service",
            "code" => "{{ text }}",
            "refs" => [],
            "vars" => [var("url", ""), var("text", "")],
            "wrapper" => false
          },
          now
        ]
      )

    koi_path = "/media/images/site/posts/1n60vo3o9p06.jpg"

    gallery = %{
      "name" => "gallery",
      "data" => %{
        "type" => "gallery",
        "uid" => Utils.generate_uid(),
        "hidden" => false,
        "data" => %{
          "images" => [
            %{
              "path" => "images/site/gallery/known.jpg",
              "title" => "Known",
              "sizes" => legacy_sizes("gallery", "known.jpg")
            },
            %{
              "path" => "/media/images/site/gallery/lost.jpg",
              "alt" => "Lost",
              "width" => 1200,
              "height" => 800,
              "sizes" => legacy_sizes("gallery", "lost.jpg", "/media/")
            }
          ]
        }
      }
    }

    blocks = [
      %{
        "type" => "module",
        "uid" => Utils.generate_uid(),
        "hidden" => false,
        "data" => %{
          "module_id" => jobs_id,
          "multi" => false,
          "vars" => [],
          "refs" => [
            picture_ref("pic", %{
              "path" => koi_path,
              "sizes" => legacy_sizes("posts", "1n60vo3o9p06.jpg", "/media/"),
              "width" => 1600,
              "height" => 1067,
              "dominant_color" => "#9a8f7e",
              "title" => "Jobb med oss",
              "alt" => "Verkstedet"
            }),
            picture_ref("pic2", %{
              "path" => "images/site/posts/trashed.jpg",
              "sizes" => legacy_sizes("posts", "trashed.jpg"),
              "width" => 800,
              "height" => 600
            }),
            picture_ref("pic3", %{
              "path" => "images/site/posts/stale.jpg",
              "sizes" => legacy_sizes("posts", "by-size.jpg"),
              "width" => 800,
              "height" => 600
            }),
            picture_ref("pic4", %{"title" => "Never picked", "path" => nil}),
            picture_ref("pic5", %{
              "path" => "images/site/posts/linked.jpg",
              "sizes" => legacy_sizes("posts", "linked.jpg")
            }),
            gallery
          ]
        }
      },
      %{
        "type" => "module",
        "uid" => Utils.generate_uid(),
        "hidden" => false,
        "data" => %{
          "module_id" => services_id,
          "multi" => true,
          "refs" => [],
          "vars" => [],
          "entries" =>
            for n <- 1..2 do
              %{
                "type" => "module_entry",
                "uid" => Utils.generate_uid(),
                "hidden" => false,
                "data" => %{"refs" => [], "vars" => [var("url", "/tjeneste-#{n}"), var("text", "Tjeneste #{n}")]}
              }
            end
        }
      }
    ]

    [[page_id]] =
      insert!(
        """
        INSERT INTO pages (uri, language, title, template, status, data, inserted_at, updated_at)
        VALUES ('kontakt', 'no', 'Kontakt', 'default.html', 1, $1, $2, $2)
        """,
        [blocks, now]
      )

    %{page: page_id, images: images, services: services_id, koi_path: koi_path}
  end

  defp ref_media(page_id) do
    rows(
      """
      SELECT r.name, i.path, i.deleted_at IS NOT NULL, r.gallery_id FROM content_refs r
      JOIN pages_blocks pb ON pb.block_id = r.block_id
      LEFT JOIN images i ON i.id = r.image_id
      WHERE pb.entry_id = $1 ORDER BY r.sequence
      """,
      [page_id]
    )
  end

  defp gallery_images(gallery_id) do
    rows(
      """
      SELECT i.path, o.config FROM galleries_gallery_objects o JOIN images i ON i.id = o.image_id
      WHERE o.gallery_id = $1 ORDER BY o.sequence
      """,
      [gallery_id]
    )
  end

  defp root_block(page_id, sequence) do
    [[id]] = rows("SELECT block_id FROM pages_blocks WHERE entry_id = $1 AND sequence = $2", [page_id, sequence])
    id
  end

  defp child_block(parent_id, sequence) do
    [[id]] = rows("SELECT id FROM content_blocks WHERE parent_id = $1 AND sequence = $2", [parent_id, sequence])
    id
  end

  defp findings do
    assert {:ok, report} = LegacyConversion.check("public")
    Enum.map(report.findings, &{&1.severity, LegacyConversion.format(&1)})
  end

  defp run_check(args), do: run_task(CheckTask, args)

  defp run_task(task, args) do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    try do
      result =
        try do
          task.run(args)
        catch
          :exit, reason -> {:exit, reason}
        end

      {result, shell_output()}
    after
      Mix.shell(shell)
    end
  end

  defp last_line(output), do: output |> Enum.reverse() |> hd()

  defp shell_output do
    receive do
      {:mix_shell, _kind, [line]} -> [line | shell_output()]
    after
      0 -> []
    end
  end

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
               ["gallery", nil, false, gallery_id]
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

  describe "mix brando.check.legacy_conversion" do
    test "finds the Villain content in the converted blocks, and lists what they have beyond it" do
      load_schema()
      %{contact: contact_id} = insert_villain_site()
      Enum.each(templates(103..1000), &migrate/1)

      assert {:ok, report} = LegacyConversion.check("public")
      assert report.findings == []
      assert report.dropped == []

      assert report.sources == [
               %{table: "content_templates", column: "data", join_table: "content_templates_blocks", entries: 0},
               %{table: "pages", column: "data", join_table: "pages_blocks", entries: 2},
               %{table: "pages_fragments", column: "data", join_table: "pages_fragments_blocks", entries: 1}
             ]

      assert {nil, ["Comparing Villain content with its blocks in public\n" | output]} = run_check([])

      assert last_line(output) =~
               "Checked 3 entries (content_templates.data, pages.data, pages_fragments.data): every Villain block"

      # A table row an editor added since
      video_block = contact_id |> root_block(0) |> child_block(1)

      rows(
        "INSERT INTO content_table_rows (block_id, sequence, inserted_at, updated_at) VALUES ($1, 2, now(), now())",
        [video_block]
      )

      assert findings() == [
               {:extra,
                ~s|pages ##{contact_id} › block 1 (container) › block 2 (module "Video") › table rows: 2 in Villain, 3 now|}
             ]

      assert {nil, output} = run_check([])
      assert last_line(output) =~ "nothing missing, 1 beyond Villain's (fails with --strict)"
      assert {{:exit, {:shutdown, 1}}, _output} = run_check(["--strict"])
    end

    test "names the refs and fragment_id the converted blocks lost" do
      load_schema()
      %{page: page_id, fragment: fragment_id} = insert_villain_site()
      Enum.each(templates(103..1000), &migrate/1)

      first_entry = page_id |> root_block(2) |> child_block(0)
      rows("DELETE FROM content_refs WHERE block_id = $1 AND name = 'p'", [first_entry])
      rows("UPDATE content_blocks SET fragment_id = NULL WHERE type = 'fragment'")

      expected = [
        "pages ##{page_id} › block 1 (fragment) › fragment_id: #{fragment_id} in Villain, none now",
        ~s|pages ##{page_id} › block 3 (module "Values") › entry 1 › refs: p missing|
      ]

      assert findings() == Enum.map(expected, &{:missing, &1})

      assert {{:exit, {:shutdown, 1}}, output} = run_check([])
      assert Enum.map(expected, &("  " <> &1)) -- output == []

      assert last_line(output) =~
               "Checked 3 entries (content_templates.data, pages.data, pages_fragments.data): 2 missing"

      # Once a Villain column is dropped, its blocks are no longer checked
      rows("ALTER TABLE pages_fragments DROP COLUMN data")

      assert {:ok, %{dropped: [%{table: "pages_fragments", column: "data", join_table: "pages_fragments_blocks"}]}} =
               LegacyConversion.check("public")

      assert {{:exit, {:shutdown, 1}}, output} = run_check([])
      assert "  pages_fragments_blocks (pages_fragments.data)" in output
      assert last_line(output) =~ "Checked 2 entries (content_templates.data, pages.data): 2 missing"
    end

    test "finds the vars of a multi module that brando_108 dropped" do
      load_schema()
      %{page: page_id} = insert_villain_site()

      # brando_108 as it shipped before it carried a multi module's own vars
      without_multi_vars = fn source ->
        multi_vars = """
                if vars = get_in(module, ["data", "vars"]) do
                  process_vars(block_id, vars)
                end
        """

        assert source =~ multi_vars
        String.replace(source, multi_vars, "")
      end

      for path <- templates(103..1000) do
        if number(path) == 108, do: migrate(path, without_multi_vars), else: migrate(path)
      end

      assert findings() == [{:missing, ~s|pages ##{page_id} › block 3 (module "Values") › vars: heading missing|}]
    end
  end
end

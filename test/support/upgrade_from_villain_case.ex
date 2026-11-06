defmodule Brando.UpgradeFromVillainCase do
  @moduledoc """
  The tests of a pre-blocks 0.53 site's upgrade, in
  `test/brando/migrations/upgrade_from_villain*_test.exs`.

  A database as a pre-blocks 0.53 site leaves it, with its content still
  Villain JSON in `pages.data` and its newest Brando migration brando_102,
  taken through every later upgrade template in order, as `mix brando.migrate`
  does on the site.

  The chain runs in a database of its own, created for this module and
  dropped afterwards, its schemas emptied before each test. The templates
  read `information_schema` for `public` and create and drop tables across
  it, so a sandboxed copy of the test database, which already has today's
  tables, cannot stand in for the old one.

  The tests are in three modules, so they run in separate partitions; the
  setup and helpers are here.
  """
  use ExUnit.CaseTemplate

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Migration.LegacyConversion
  alias Brando.Utils
  alias BrandoIntegration.Repo
  alias Mix.Tasks.Brando.Check.LegacyConversion, as: CheckTask

  using do
    quote do
      import Brando.UpgradeFromVillainCase

      @moduletag timeout: :timer.minutes(5)
    end
  end

  @schema "test/fixtures/upgrade/brando_102_schema.sql"
  @templates Application.app_dir(:brando, "priv/templates/brando.upgrade/migrations")
  # brando_133 as sites ran it until it created images for legacy media that
  # matched no row: it linked pictures by path only and left the rest empty
  @shipped_133 "test/fixtures/upgrade/brando_133_transfer_ref_media_data.shipped.txt"
  # Each template runs as version `@version + its number`, and the copies the
  # repair task reads the conversion's time through are stubs with those
  # versions
  @version 20_260_101_000_000
  @copies ~w(brando_133_transfer_ref_media_data brando_175_add_updated_by)
  # Database-wide DDL waits for checkpoints and other sessions, which on a
  # loaded machine takes longer than a query's default 15 seconds
  @ddl [timeout: :timer.minutes(2)]

  # One database for the module, created once: `CREATE DATABASE` and
  # `DROP DATABASE` are what time out on a loaded machine, not the tests.
  # Each test empties its schemas instead.
  setup_all do
    database = "#{Repo.config()[:database]}_villain_#{Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)}"
    storage = Repo.config() |> Keyword.put(:database, database) |> Keyword.merge(@ddl)

    :ok = Ecto.Adapters.Postgres.storage_up(storage)
    # A connection the pool has not closed yet does not hold the drop up
    on_exit(fn -> :ok = Ecto.Adapters.Postgres.storage_down(Keyword.put(storage, :force_drop, true)) end)

    %{database: database}
  end

  setup %{database: database} do
    # The test repo's own connection settings (parsed from its url, which CI
    # gives credentials in), pointed at the new database and out of the sandbox
    repo_config =
      Repo.config()
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

    # What the previous test's chain made, dropped: `public` starts empty, as
    # in a new database
    for [schema] <- rows("SELECT nspname FROM pg_namespace WHERE nspname !~ '^pg_' AND nspname <> 'information_schema'"),
        do: Repo.query!(~s(DROP SCHEMA "#{schema}" CASCADE), [], @ddl)

    Repo.query!("CREATE SCHEMA public", [], @ddl)

    # Templates that walk the site's Blueprints (`Brando.Blueprint.list_blueprints/0`)
    # would find the test app's, whose tables this database never had. The
    # Villain content here lives in Brando's own tables, which the templates
    # find through `information_schema`.
    otp_app = Application.get_env(:brando, :otp_app)
    Application.put_env(:brando, :otp_app, :eex)
    on_exit(fn -> Application.put_env(:brando, :otp_app, otp_app) end)

    copies = Path.join(System.tmp_dir!(), "#{database}_migrations_#{System.unique_integer([:positive])}")
    File.mkdir_p!(copies)
    on_exit(fn -> File.rm_rf!(copies) end)

    for name <- @copies do
      [_, number] = Regex.run(~r/brando_(\d+)_/, name)
      File.write!(Path.join(copies, "#{@version + String.to_integer(number)}_#{name}.exs"), "")
    end

    put_test_env(:public_migrations_path, copies)

    %{copies: copies}
  end

  @doc "The migration version the templates run under, plus their number."
  def version, do: @version

  def templates(range) do
    @templates
    |> Path.join("brando_*.exs")
    |> Path.wildcard()
    |> Enum.map(&{number(&1), &1})
    |> Enum.filter(fn {number, _} -> number in range end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  def number(path) do
    [_, number] = Regex.run(~r/brando_(\d+)_/, Path.basename(path))
    String.to_integer(number)
  end

  # `edit` changes the template's source before it is compiled
  def migrate(path, edit \\ & &1) do
    module = load_template(path, path |> File.read!() |> edit.())

    try do
      :ok = Ecto.Migrator.up(Repo, @version + number(path), module, log: false)
    rescue
      error -> reraise RuntimeError, "#{Path.basename(path)}: #{Exception.message(error)}", __STACKTRACE__
    after
      :code.purge(module)
      :code.delete(module)
    end
  end

  # Compiles a template's source once per run and loads that module again
  # after: each test runs the whole chain, about 120 templates, and compiling
  # them took a third of its time. Keyed by the source, which `edit` may change.
  defp load_template(path, source) do
    key = {__MODULE__, :template, path, :erlang.phash2(source)}

    case :persistent_term.get(key, nil) do
      nil ->
        [{module, bytecode}] = Code.compile_string(source, path)
        :persistent_term.put(key, {module, bytecode})
        module

      {module, bytecode} ->
        :code.purge(module)
        {:module, ^module} = :code.load_binary(module, String.to_charlist(path), bytecode)
        module
    end
  end

  # pg_dump output, one statement at a time; a `;` inside a function body
  # (between `$$`) does not end one
  def load_schema do
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

  def odd_dollar_quotes?(sql), do: sql |> String.split("$$") |> length() |> rem(2) == 0

  def rows(sql, params \\ []), do: Repo.query!(sql, params).rows

  def insert!(sql, params), do: [[_id]] = rows(sql <> " RETURNING id", params)

  def villain_video(name, extra \\ %{}) do
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

  def text_ref(name, text) do
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

  def var(key, value, type \\ "string"),
    do: %{"key" => key, "type" => type, "label" => key, "value" => value, "important" => true}

  def table_ref(name, cells) do
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
  def insert_villain_site do
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

  def picture_ref(name, data) do
    %{"name" => name, "data" => %{"type" => "picture", "uid" => Utils.generate_uid(), "hidden" => false, "data" => data}}
  end

  def legacy_sizes(dir, file, prefix \\ "") do
    Map.new(~w(micro thumb small medium large xlarge), &{&1, "#{prefix}images/site/#{dir}/#{&1}/#{file}"})
  end

  def insert_image!(path, extra \\ "") do
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
  def insert_koi_page do
    now = ~N[2023-11-01 12:00:00]

    images = %{
      linked: insert_image!("images/site/posts/linked.jpg"),
      deleted: insert_image!("images/site/posts/trashed.jpg", ", '2023-06-01'"),
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
          Enum.map_join(~w(pic pic2 pic3 pic4 pic5 gallery media), &"{% ref refs.#{&1} %}"),
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
            gallery,
            # A media slot nobody filled. 0.53 rendered it as nothing, and its
            # templates only lent their settings to the picture or gallery an
            # editor picked (`path`, `sizes` and `images` are protected), so
            # an image named here was never shown and is not a loss.
            %{
              "name" => "media",
              "data" => %{
                "type" => "media",
                "uid" => Utils.generate_uid(),
                "hidden" => false,
                "data" => %{
                  "available_blocks" => ["picture", "gallery"],
                  "template_picture" => %{"path" => "images/site/posts/template-only.jpg", "img_class" => "wide"},
                  "template_gallery" => %{"images" => [%{"path" => "images/site/gallery/template-only.jpg"}]}
                }
              }
            }
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

    # A free-standing picture without a row, which brando_108 wraps
    hero = %{
      "type" => "picture",
      "uid" => Utils.generate_uid(),
      "hidden" => false,
      "data" => %{
        "path" => "/media/images/site/posts/hero.jpg",
        "sizes" => legacy_sizes("posts", "hero.jpg", "/media/"),
        "width" => 2000,
        "height" => 1000
      }
    }

    [[page_id]] =
      insert!(
        """
        INSERT INTO pages (uri, language, title, template, status, data, inserted_at, updated_at)
        VALUES ('kontakt', 'no', 'Kontakt', 'default.html', 1, $1, $2, $2)
        """,
        [blocks ++ [hero], now]
      )

    %{page: page_id, images: images, services: services_id, koi_path: koi_path}
  end

  # The chain from brando_103 on, with brando_133 as sites ran it before it
  # created images for legacy media that matched no row
  def migrate_with_shipped_133 do
    shipped = fn _source -> File.read!(@shipped_133) end
    for path <- templates(103..1000), do: migrate(path, if(number(path) == 133, do: shipped, else: & &1))
  end

  def ref_media(page_id) do
    rows(
      """
      SELECT r.name, i.path, i.deleted_at IS NOT NULL, r.gallery_id FROM content_refs r
      JOIN pages_blocks pb ON pb.block_id = r.block_id
      LEFT JOIN images i ON i.id = r.image_id
      WHERE pb.entry_id = $1 ORDER BY pb.sequence, r.sequence
      """,
      [page_id]
    )
  end

  def gallery_images(gallery_id) do
    rows(
      """
      SELECT i.path, o.config FROM galleries_gallery_objects o JOIN images i ON i.id = o.image_id
      WHERE o.gallery_id = $1 ORDER BY o.sequence
      """,
      [gallery_id]
    )
  end

  def root_block(page_id, sequence) do
    [[id]] = rows("SELECT block_id FROM pages_blocks WHERE entry_id = $1 AND sequence = $2", [page_id, sequence])
    id
  end

  def child_block(parent_id, sequence) do
    [[id]] = rows("SELECT id FROM content_blocks WHERE parent_id = $1 AND sequence = $2", [parent_id, sequence])
    id
  end

  def findings do
    assert {:ok, report} = LegacyConversion.check("public")
    Enum.map(report.findings, &{&1.severity, LegacyConversion.format(&1)})
  end

  def run_check(args), do: run_task(CheckTask, args)

  def run_task(task, args) do
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

  def last_line(output), do: output |> Enum.reverse() |> hd()

  def summary_line(output), do: Enum.find(output, &(&1 =~ " refs "))

  def shell_output do
    receive do
      {:mix_shell, _kind, [line]} -> [line | shell_output()]
    after
      0 -> []
    end
  end

  # The page with its media lost by the shipped brando_133, how the repair
  # sees it, and a way to tell nothing was written
  def lost_media do
    load_schema()
    %{page: about} = insert_villain_site()
    koi = insert_koi_page()
    migrate_with_shipped_133()

    state = fn ->
      {ref_media(koi.page), rows("SELECT id, path, deleted_at FROM images ORDER BY id"),
       rows("SELECT id, gallery_id, image_id, sequence, config FROM galleries_gallery_objects ORDER BY id"),
       rows("SELECT id, video_id FROM content_refs ORDER BY id"), rows("SELECT id, deleted_at FROM videos ORDER BY id")}
    end

    koi |> Map.put(:state, state) |> Map.put(:about, about)
  end

  def repairs(opts \\ []) do
    assert {:ok, %{repairs: repairs}} = Brando.Migration.LegacyMediaRepair.run("public", opts)
    Enum.map(repairs, fn {finding, action} -> {finding.message |> String.split(":") |> hd(), action} end)
  end

  def utc_in(seconds), do: NaiveDateTime.add(NaiveDateTime.utc_now(), seconds) |> NaiveDateTime.truncate(:second)
end

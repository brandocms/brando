defmodule Brando.Doctor.ChecksTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Doctor.Checks
  alias Brando.Doctor.Context
  alias Brando.Doctor.Result
  alias Brando.Factory
  alias Brando.Images.Image
  alias Brando.Images.Processing

  @now ~U[2026-10-07 12:00:00Z]

  defp context(opts \\ []), do: Context.new(Keyword.merge([now: @now, locale: "en"], opts))

  defp tmp_dir(name) do
    dir = Path.join(System.tmp_dir!(), "brando_doctor_#{name}_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  describe "Versions" do
    @requirements %{elixir: "~> 1.18", otp: 27, phoenix: "1.8.15", live_view: "1.2.12"}
    @versions %{brando: "0.55.0", elixir: "1.20.3", otp: "28", phoenix: "1.8.15", live_view: "1.2.12"}

    test "supported versions pass" do
      assert %Result{status: :ok, summary: "Elixir 1.20.3 · OTP 28"} = Checks.Versions.evaluate(@versions, @requirements)
    end

    test "an unsupported version is an error that names it" do
      result = Checks.Versions.evaluate(%{@versions | otp: "26", phoenix: "1.8.10"}, @requirements)
      assert result.status == :error
      assert result.summary =~ "OTP 26, needs >= 27"
      assert result.summary =~ "Phoenix 1.8.10, needs 1.8.15"
    end

    test "the requirements come from Brando's mix.exs" do
      assert %{elixir: "~> " <> _, phoenix: phoenix, live_view: live_view} = Checks.Versions.requirements()
      assert phoenix && live_view
      assert %Result{status: :ok} = Checks.Versions.run(context())
    end
  end

  describe "Migrations" do
    @empty %{public: [], tenants: [], drift: [], missing: [], ran: 12}

    test "up to date" do
      assert %Result{status: :ok, summary: "up to date", items: ["12 run"]} = Checks.Migrations.evaluate(@empty)
      assert %Result{status: :ok} = Checks.Migrations.run(context())
    end

    test "pending migrations are an error, with the command for each kind" do
      public = Checks.Migrations.evaluate(%{@empty | public: [{20_260_101_000_000, "add_things"}]})
      assert public.status == :error
      assert public.summary == "1 migration not run"
      assert public.fix == "run mix brando.migrate"
      assert public.items == ["20260101000000_add_things"]

      tenants = Checks.Migrations.evaluate(%{@empty | tenants: [{"acme/live", [{1, "a"}, {2, "b"}]}]})
      assert tenants.summary == "2 migrations not run"
      assert tenants.fix == "run mix brando.migrate --tenants"
      assert "[acme/live] 1_a" in tenants.items
    end

    test "pending copies that differ from Brando's templates are a warning" do
      result =
        Checks.Migrations.evaluate(%{
          @empty
          | drift: [{:outdated, "priv/repo/migrations/1_brando_02_x.exs", "t/brando_02_x.exs"}]
        })

      assert result.status == :warning
      assert result.fix =~ "mix brando.migrations.check --update"
      assert result.items == ["1_brando_02_x.exs differs from brando_02_x.exs"]
    end

    test "lists Brando migrations a project that copies them has not copied" do
      templates = tmp_dir("templates")
      migrations = tmp_dir("migrations")
      for name <- ~w(brando_01_a.exs brando_02_b.exs brando_03_c.exs), do: File.write!(Path.join(templates, name), "")

      # A project without copies is built some other way: nothing to report
      assert Checks.Migrations.missing_templates(migrations, templates) == []

      File.write!(Path.join(migrations, "20200101000000_brando_01_a.exs"), "")
      # Renumbered since: matched by what follows the number
      File.write!(Path.join(migrations, "20200101000001_brando_09_b.exs"), "")
      assert Checks.Migrations.missing_templates(migrations, templates) == ["brando_03_c.exs"]

      result = Checks.Migrations.evaluate(%{@empty | missing: ["brando_03_c.exs"]})
      assert result.status == :warning
      assert result.fix =~ "mix brando.gen.migrations"
    end
  end

  describe "Oban" do
    @queues for name <- ~w(default content_events webhooks search_index),
                do: %{queue: name, limit: 1, paused: false, live: false}

    test "configured queues and no stuck or discarded jobs" do
      assert %Result{status: :ok, summary: "4 queues, 0 stuck"} =
               Checks.Oban.evaluate(%{testing: nil, queues: @queues, stuck: [], discarded: []})
    end

    test "warns when the queues for content events, webhooks and search are missing" do
      queues = Enum.reject(@queues, &(&1.queue == "webhooks"))
      result = Checks.Oban.evaluate(%{testing: nil, queues: queues, stuck: [], discarded: []})
      assert result.status == :warning
      assert result.summary == "3 queues, 0 stuck · no webhooks queue"
      assert result.fix =~ "webhooks: [limit: …]"

      queues = [%{queue: "default", limit: 1, paused: false, live: false}]
      result = Checks.Oban.evaluate(%{testing: nil, queues: queues, stuck: [], discarded: []})
      assert result.summary =~ "no content_events, webhooks, search_index queue"

      # Not when jobs run inline
      assert %Result{status: :ok} = Checks.Oban.evaluate(%{testing: :inline, queues: queues, stuck: [], discarded: []})
    end

    test "queues read from the running Oban, with a paused one" do
      queues = [
        %{queue: "default", limit: 1, paused: false, live: true},
        %{queue: "content_events", limit: 1, paused: false, live: true},
        %{queue: "webhooks", limit: 5, paused: false, live: true},
        %{queue: "search_index", limit: 2, paused: false, live: true},
        %{queue: "mail", limit: 2, paused: true, live: true}
      ]

      result = Checks.Oban.evaluate(%{testing: nil, queues: queues, stuck: [], discarded: []})
      assert result.status == :warning
      assert result.summary == "4 running, 0 stuck · 1 paused"
    end

    test "no queues is an error, unless jobs run inline" do
      assert %Result{status: :error} = Checks.Oban.evaluate(%{testing: nil, queues: [], stuck: [], discarded: []})
      assert %Result{status: :ok} = Checks.Oban.evaluate(%{testing: :inline, queues: [], stuck: [], discarded: []})
    end

    test "finds jobs stuck for an hour and jobs discarded in the last day" do
      repo = Brando.Repo.repo()
      long_ago = usec(DateTime.add(@now, -2 * 3600, :second))

      insert = fn attrs ->
        repo.insert!(struct(Oban.Job, Map.merge(%{worker: "MyApp.Worker", queue: "default", args: %{}}, attrs)))
      end

      stuck = insert.(%{state: "available", scheduled_at: long_ago})
      insert.(%{state: "available", scheduled_at: usec(@now)})

      discarded =
        insert.(%{state: "discarded", discarded_at: long_ago, errors: [%{"error" => "** (RuntimeError) nope\nstack"}]})

      insert.(%{state: "discarded", discarded_at: usec(DateTime.add(@now, -3 * 86_400, :second))})

      result =
        Checks.Oban.run(context(oban: [queues: [default: 1, content_events: 1, webhooks: 5, search_index: 2]]))

      assert result.status == :warning
      assert result.summary == "4 queues, 1 stuck, 1 discarded in 24 h"
      assert Enum.any?(result.items, &(&1 =~ "##{stuck.id} MyApp.Worker (available"))

      assert Enum.any?(
               result.items,
               &(&1 =~ ~r/##{discarded.id} MyApp.Worker \(discarded.*\): \*\* \(RuntimeError\) nope$/)
             )
    end
  end

  defp usec(datetime), do: %{datetime | microsecond: {0, 6}}

  describe "Configuration" do
    test "the test application's settings are in place" do
      assert %Result{status: :ok, items: items} = Checks.Configuration.run(context())
      assert Enum.any?(items, &(&1 =~ "Mailer: "))
    end

    test "no mailer is a warning" do
      put_test_env(:mailer, nil)
      assert {:warning, "Mailer: not set", "no mailer"} = Checks.Configuration.mailer()
      assert %Result{status: :warning, summary: "no mailer"} = Checks.Configuration.run(context())
    end

    test "an enabled CDN without a bucket or credentials is an error" do
      images = Application.get_env(:brando, Brando.Images, [])
      put_test_env(Brando.Images, Keyword.put(images, :cdn, %Brando.CDN.Config{enabled: true, s3: :default}))
      put_test_env(Brando.CDN.S3Config, nil)

      assert {:error, item, "Images CDN incomplete"} = Checks.Configuration.cdn(Brando.Images)
      assert item == "Images CDN: missing bucket, media_url, Brando.CDN.S3Config"
      assert %Result{status: :error} = Checks.Configuration.run(context())
    end

    test "a configured Assistant needs its key" do
      put_test_env(Brando.AI.Agent, model: "anthropic:claude-opus-5-5")
      put_test_env(Brando.AI, providers: [anthropic: [api_key: nil]])
      System.delete_env("ANTHROPIC_API_KEY")

      assert {:warning, _item, "no API key for the Assistant"} = Checks.Configuration.assistant()
    end

    test "findings combine into one summary at the worst status" do
      result =
        Checks.Configuration.evaluate([
          {:ok, "Endpoint URL: https://example.com", nil},
          {:warning, "Mailer: not set", "no mailer"},
          {:error, "Images CDN: missing bucket", "Images CDN incomplete"}
        ])

      assert result.status == :error
      assert result.summary == "no mailer, Images CDN incomplete"
    end
  end

  describe "AdminAssets" do
    defp backend(package, files \\ %{}) do
      root = tmp_dir("assets")
      backend = Path.join(root, "assets/backend")
      File.mkdir_p!(backend)
      File.write!(Path.join(backend, "package.json"), Jason.encode!(package))

      for {path, json} <- files do
        File.mkdir_p!(Path.dirname(Path.join(backend, path)))
        File.write!(Path.join(backend, path), Jason.encode!(json))
      end

      root
    end

    @yalc %{"dependencies" => %{"@brandocms/brandojs" => "file:.yalc/@brandocms/brandojs"}}

    test "the .yalc copy matches Brando's version" do
      root = backend(@yalc, %{".yalc/@brandocms/brandojs/package.json" => %{"version" => Brando.version()}})
      assert %Result{status: :ok, summary: ".yalc brandojs " <> _} = Checks.AdminAssets.run(context(root: root))
    end

    test "an older .yalc publish is a warning, with the fix" do
      root = backend(@yalc, %{".yalc/@brandocms/brandojs/package.json" => %{"version" => "0.55.0-beta.0"}})
      dir = Path.join(root, "assets/backend")

      result = Checks.AdminAssets.evaluate(dir, "0.55.0-dev")
      assert result.status == :warning
      assert result.summary =~ "0.55.0-beta.0"
      assert result.fix =~ "0.55.0-dev"
    end

    test "a .yalc copy beside a plain version" do
      root =
        backend(%{"dependencies" => %{"@brandocms/brandojs" => "0.55.0"}}, %{
          ".yalc/@brandocms/brandojs/package.json" => %{"version" => "0.54.0"}
        })

      result = Checks.AdminAssets.evaluate(Path.join(root, "assets/backend"), "0.55.0")
      assert result.status == :warning
      assert result.summary == ".yalc brandojs 0.54.0"
      assert result.fix =~ "npx yalc update"
    end

    test "a checkout linked by path" do
      root = tmp_dir("linked")
      File.mkdir_p!(Path.join(root, "brandojs"))
      File.write!(Path.join(root, "brandojs/package.json"), Jason.encode!(%{"version" => "0.55.0"}))
      backend = Path.join(root, "assets/backend")
      File.mkdir_p!(backend)

      File.write!(
        Path.join(backend, "package.json"),
        Jason.encode!(%{"dependencies" => %{"@brandocms/brandojs" => "link:../../brandojs"}})
      )

      assert %Result{status: :ok, summary: "linked to ../../brandojs, brandojs 0.55.0"} =
               Checks.AdminAssets.evaluate(backend, "0.55.0")

      assert %Result{status: :warning} = Checks.AdminAssets.evaluate(backend, "0.56.0")
    end

    test "not installed is an error, and no backend is skipped" do
      root = backend(%{"dependencies" => %{"@brandocms/brandojs" => "0.55.0"}})
      assert %Result{status: :error, summary: "brandojs not installed"} = Checks.AdminAssets.run(context(root: root))
      assert %Result{status: :skipped} = Checks.AdminAssets.run(context(root: tmp_dir("empty")))
    end

    test "reads the source tree" do
      assert Checks.AdminAssets.needs_source?()
    end
  end

  describe "ImageConfigs" do
    test "images made with an older config are a warning per config" do
      for target <-
            Brando.Repo.all(from i in Image, where: not is_nil(i.config_target), distinct: true, select: i.config_target) do
        Brando.Repo.update_all(from(i in Image, where: i.config_target == ^target),
          set: [config_fingerprint: Processing.current_fingerprint(target)]
        )
      end

      assert %Result{status: :ok} = Checks.ImageConfigs.run(context())

      Factory.insert(:image, config_fingerprint: "0123456789ab")
      Factory.insert(:image, config_fingerprint: nil, path: "image/2.jpg")

      result = Checks.ImageConfigs.run(context())
      assert result.status == :warning

      assert result.summary ==
               "1 config changed since its images were made (1 image); 1 image was made before Brando recorded its settings"

      assert result.items == ["default: 1 image", "default: 1 image without recorded settings"]
      assert {"#utils-image-sizes", _label} = result.link
    end

    test "images made before configs were recorded are not reported as changed configs" do
      Brando.Repo.update_all(from(i in Image, where: not is_nil(i.config_target)), set: [config_fingerprint: nil])
      Factory.insert(:image, config_fingerprint: nil, path: "image/3.jpg")

      result = Checks.ImageConfigs.run(context())
      assert result.status == :warning
      refute result.summary =~ "config changed"
      assert result.summary =~ "made before Brando recorded"
      assert result.fix =~ "once"
    end
  end

  describe "Modules" do
    test "blocks behind their module's version are a warning" do
      assert %Result{status: :ok} = Checks.Modules.run(context())

      user = Factory.insert(:random_user)
      module = Factory.insert(:module, name: %{"en" => "Hero"}, uid: "hero-doctor")

      for version <- [nil, 0] do
        %Brando.Content.Block{}
        |> Ecto.Changeset.change(%{
          uid: Brando.Utils.generate_uid(),
          type: :module,
          module_id: module.id,
          module_version: version,
          creator_id: user.id,
          sequence: 0
        })
        |> Brando.Repo.insert!()
      end

      result = Checks.Modules.run(context())
      assert result.status == :warning
      assert result.summary == "2 blocks on outdated module versions"
      assert result.items == ["Hero (hero-doctor): 2 blocks"]
      assert {BrandoAdmin.Content.ModuleListLive, _} = result.link
    end
  end

  describe "Sitemap" do
    test "not generated is an error" do
      assert %Result{status: :error, summary: "not generated"} = Checks.Sitemap.evaluate([{nil, nil}], @now)
    end

    test "older than two days is a warning" do
      result = Checks.Sitemap.evaluate([{nil, DateTime.add(@now, -3 * 86_400, :second)}], @now)
      assert result.status == :warning
      assert result.summary == "last generated 3 days ago"
    end

    test "recent passes" do
      assert %Result{status: :ok, summary: "generated 5 hours ago"} =
               Checks.Sitemap.evaluate([{nil, DateTime.add(@now, -5 * 3600, :second)}], @now)
    end

    test "an application without a sitemap module is told how to add one" do
      assert %Result{status: :warning, fix: "run mix brando.gen.sitemap"} = Checks.Sitemap.run(context(), false)
    end
  end

  describe "Robots" do
    test "served by Brando" do
      assert %Result{status: :ok} = Checks.Robots.evaluate(Brando.SEOController, false)
    end

    test "routed elsewhere, or behind a static file" do
      assert %Result{status: :warning, summary: "not served by Brando"} = Checks.Robots.evaluate(nil, false)
      assert %Result{status: :warning} = Checks.Robots.evaluate(Brando.SEOController, true)
    end
  end

  describe "JSONLD" do
    test "a complete identity passes" do
      identities = [{nil, [%{language: "en", name: "Univers", logo?: true}]}]
      assert %Result{status: :ok} = Checks.JSONLD.evaluate(identities, "https://univers.no")
    end

    test "a missing logo or name is a warning per language" do
      identities = [{nil, [%{language: "en", name: "Univers", logo?: false}, %{language: "no", name: "", logo?: true}]}]
      result = Checks.JSONLD.evaluate(identities, "https://univers.no")
      assert result.status == :warning
      assert result.items == ["en: no logo", "no: no name"]
    end

    test "no identity or no URL is an error" do
      assert %Result{status: :error} = Checks.JSONLD.evaluate([{"acme/live", []}], "https://univers.no")
      assert %Result{status: :error} = Checks.JSONLD.evaluate([{nil, [%{language: "en", name: "U", logo?: true}]}], "")
    end

    test "reads the identities" do
      assert %Result{status: status} = Checks.JSONLD.run(context())
      assert status in [:ok, :warning]
    end
  end

  describe "AltText" do
    test "counts images without alt text per language" do
      insert = fn path, alt -> Factory.insert(:image, path: path, status: :processed, alt: alt) end
      insert.("images/doctor/bare.jpg", nil)
      insert.("images/doctor/half.jpg", %{"en" => "A ferry"})
      insert.("images/doctor/done.jpg", %{"en" => "A ferry", "no" => "En ferje"})

      result = Checks.AltText.run(context())
      assert result.status == :warning
      assert result.summary =~ "1 image without alt (en)"
      assert result.summary =~ "2 images without alt (no)"
      assert Enum.any?(result.items, &(&1 =~ ~r/^no: 2 of \d+ without alt text/))
    end

    test "full coverage passes" do
      assert %Result{status: :ok} = Checks.AltText.evaluate([{nil, %{"en" => {0, 4}, "no" => {0, 4}}}])
    end
  end

  describe "Deprecations" do
    @deprecated_calls %{
      {Brando.HTML, :picture_tag, 2} => "Use <.picture>",
      {Brando.HTML, :video_tag, 2} => "Use <.video>"
    }

    defp scan(code), do: code |> Code.string_to_quoted!() |> Checks.Deprecations.scan(@deprecated_calls)

    test "follows aliases, imports and pipes" do
      code = """
      defmodule MyApp.Page do
        alias Brando.HTML
        alias Brando.HTML, as: Markup
        import Brando.HTML, only: [video_tag: 2]

        def a(img), do: HTML.picture_tag(img, [])
        def b(img), do: img |> Markup.picture_tag([])
        def c(img), do: Brando.HTML.picture_tag(img, [])
        def d(video), do: video_tag(video, [])
        def e(img), do: HTML.picture_tag(img)
        def f(img), do: MyApp.HTML.picture_tag(img, [])
      end
      """

      assert [
               %{line: 6, call: "Brando.HTML.picture_tag/2", reason: "Use <.picture>"},
               %{line: 7},
               %{line: 8},
               %{line: 9, call: "Brando.HTML.video_tag/2"}
             ] = scan(code)
    end

    test "a local function of the same name is not a call without an import" do
      assert scan("defmodule A do\n  def x(v), do: video_tag(v, [])\nend") == []
    end

    test "scans the project's lib/ and reports file and line" do
      root = tmp_dir("lib")
      File.mkdir_p!(Path.join(root, "lib/my_app"))

      File.write!(Path.join(root, "lib/my_app/page.ex"), """
      defmodule MyApp.Page do
        def cover(img), do: Brando.HTML.picture_tag(img, [])
      end
      """)

      File.write!(Path.join(root, "lib/my_app/clean.ex"), "defmodule MyApp.Clean do\nend\n")

      result = Checks.Deprecations.run(context(root: root))
      assert result.status == :warning
      assert result.summary == "1 call in lib/ (1 file)"
      assert [item] = result.items
      assert item =~ "lib/my_app/page.ex:2 Brando.HTML.picture_tag/2: "

      assert %Result{status: :ok, summary: "none in lib/"} = Checks.Deprecations.run(context(root: tmp_dir("clean")))
    end

    test "knows Brando's deprecated functions" do
      assert Map.has_key?(Checks.Deprecations.deprecated(), {Brando.HTML, :picture_tag, 2})
      assert Checks.Deprecations.needs_source?()
    end
  end
end

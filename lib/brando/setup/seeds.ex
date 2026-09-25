defmodule Brando.Setup.Seeds do
  @moduledoc """
  Default content for a freshly installed application.

  Creates the content a new site needs before its first request succeeds:
  identity and SEO per configured language, a set of modules, a published
  `index` page built from them, a main navigation menu and a footer fragment.

  Every step is skipped when its content already exists, so the seeds are safe
  to rerun. Nothing here is a migration path: existing content is never
  modified or removed.

  Run through `mix brando.setup` or `mix brando.gen.seeds`.
  """

  alias Brando.Cache
  alias Brando.Content
  alias Brando.Navigation
  alias Brando.Pages
  alias Brando.Sites
  alias Brando.Villain.Blocks.HeaderBlock
  alias Brando.Villain.Blocks.TextBlock

  @hero_uid "brando-default-hero"
  @steps_uid "brando-default-steps"
  @cards_uid "brando-default-cards"
  @tips_uid "brando-default-tips"
  @terminal_uid "brando-default-terminal"
  @closing_uid "brando-default-closing"
  @footer_uid "brando-default-footer"

  @docs_url "https://hexdocs.pm/brando"

  @doc """
  Seeds default content for every configured language.

  Returns `{:ok, report}` where report counts what was created and what already
  existed. Creation failures raise, since a half-seeded site is harder to
  reason about than a failed setup step.
  """
  @spec run(Brando.Users.User.t(), keyword()) :: {:ok, map()}
  def run(user, opts \\ []) do
    languages = opts[:languages] || languages()
    modules = modules(user)

    report =
      Enum.reduce(languages, %{created: [], skipped: []}, fn language, report ->
        report
        |> track(:"identity (#{language})", fn -> identity(language) end)
        |> track(:"seo (#{language})", fn -> seo(language) end)
        |> track(:"menu (#{language})", fn -> menu(language, user) end)
        |> track(:"page (#{language})", fn -> index_page(language, user, modules) end)
      end)

    Cache.Identity.set()
    Cache.SEO.set()
    Cache.Navigation.set()

    {:ok, Map.put(report, :modules, modules)}
  end

  defp track(report, label, fun) do
    case fun.() do
      :exists -> Map.update!(report, :skipped, &[label | &1])
      _created -> Map.update!(report, :created, &[label | &1])
    end
  end

  defp languages do
    :languages
    |> Brando.config()
    |> Enum.map(&String.to_existing_atom(&1[:value]))
  end

  # The framework defaults are placeholders ("Organization name"), which would
  # otherwise show up in the header and the page title of a new site.
  defp identity(language) do
    case Sites.get_identity(%{matches: %{language: language}}) do
      {:ok, _identity} ->
        :exists

      {:error, _} ->
        language
        |> Sites.create_default_identity()
        |> Ecto.Changeset.change(%{name: site_name(), title: site_name(), title_prefix: nil})
        |> Brando.Repo.update!()
    end
  end

  defp seo(language) do
    case Sites.get_seo(%{matches: %{language: language}}) do
      {:ok, _seo} -> :exists
      {:error, _} -> Sites.create_default_seo(language)
    end
  end

  # Checked against the repo rather than `Navigation.get_menu/2`, which reads
  # the navigation cache and reports not_found before the cache is warmed.
  defp menu(language, user) do
    case Brando.Repo.get_by(Navigation.Menu, key: "main", language: language) do
      %Navigation.Menu{} ->
        :exists

      nil ->
        {:ok, menu} =
          Navigation.create_menu(
            %{
              title: "Main menu",
              key: "main",
              language: to_string(language),
              status: :published,
              sequence: 0,
              items: [
                menu_item("home", 0, "Home", "/"),
                menu_item("admin", 1, "Admin", "/admin")
              ]
            },
            user
          )

        menu
    end
  end

  defp menu_item(key, sequence, text, url) do
    %{
      key: key,
      status: :published,
      sequence: sequence,
      link: %{
        type: :link,
        key: "link",
        label: "Link",
        link_type: :url,
        link_text: text,
        value: url
      }
    }
  end

  # ── Modules ───────────────────────────────────────────────────────────────

  # Modules are global, so they are seeded once regardless of language. Their
  # uid carries module identity across imports and upgrades, so a stable uid is
  # what makes a rerun a no-op instead of a duplicate.
  defp modules(user) do
    %{
      hero: upsert_module(@hero_uid, user, &hero_module/0),
      steps: upsert_module(@steps_uid, user, &steps_module/0),
      cards: upsert_module(@cards_uid, user, &cards_module/0),
      tips: upsert_module(@tips_uid, user, &tips_module/0),
      terminal: upsert_module(@terminal_uid, user, &terminal_module/0),
      closing: upsert_module(@closing_uid, user, &closing_module/0),
      footer: upsert_module(@footer_uid, user, &footer_module/0)
    }
  end

  # Modules carry no creator, so the seeding account is only needed for the
  # content that references them.
  defp upsert_module(uid, _user, build) do
    case Brando.Repo.get_by(Content.Module, uid: uid) do
      nil -> Brando.Repo.insert!(build.())
      module -> module
    end
  end

  defp hero_module do
    %Content.Module{
      uid: @hero_uid,
      name: "Hero",
      namespace: "general",
      help_text:
        "Page opening: a mono eyebrow, the headline, a lead paragraph and a four-part fact row. " <>
          "The headline may carry a second line wrapped in <span class=\"soft\"> to step it back.",
      class: "hero",
      code: """
      <section b-tpl="hero">
        <div class="inner">
          <div class="eyebrow">
            <span class="dot" aria-hidden="true"></span>
            {% ref refs.eyebrow %}
            <span class="rule" aria-hidden="true"></span>
          </div>

          {% ref refs.title %}

          <div class="lead">{% ref refs.lead %}</div>

          <div class="actions">
            <a class="button" href="/admin">Open the admin</a>
            <a class="textlink" href="#{@docs_url}" target="_blank" rel="noopener">Read the guides &#8599;</a>
          </div>

          <div class="ledger">
      #{Enum.map_join(1..4, "\n", &ledger_entry/1)}
          </div>
        </div>
      </section>
      """,
      sequence: 0,
      vars: [],
      refs:
        [
          text_ref("eyebrow", "<p>Eyebrow</p>", 0),
          header_ref("title", 1, "Headline", 1),
          text_ref("lead", "<p>Lead paragraph</p>", 2)
        ] ++
          Enum.flat_map(1..4, fn n ->
            [
              text_ref("ledger_#{n}_value", "<p>One</p>", 2 + n * 2 - 1),
              text_ref("ledger_#{n}_label", "<p>Label</p>", 2 + n * 2)
            ]
          end)
    }
  end

  defp ledger_entry(n) do
    """
          <div class="entry">
            <div class="value">{% ref refs.ledger_#{n}_value %}</div>
            <div class="key">{% ref refs.ledger_#{n}_label %}</div>
          </div>\
    """
  end

  defp steps_module do
    %Content.Module{
      uid: @steps_uid,
      name: "Steps",
      namespace: "general",
      help_text: "A numbered three-step sequence, each step ending in a command to run.",
      class: "steps",
      code: """
      <section b-tpl="steps">
        <div class="inner">
          <div class="section-head">
            <span class="label">01 &mdash; Quick start</span>
            {% ref refs.heading %}
            <span class="rule" aria-hidden="true"></span>
            <span class="note">About five minutes</span>
          </div>

          <div class="steps">
      #{Enum.map_join(1..3, "\n", &step_entry/1)}
          </div>
        </div>
      </section>
      """,
      sequence: 1,
      vars: [],
      refs:
        [header_ref("heading", 2, "Section heading", 0)] ++
          Enum.flat_map(1..3, fn n ->
            [
              header_ref("step_#{n}_title", 3, "Step #{n}", n * 3 - 2),
              text_ref("step_#{n}_text", "<p>Step description</p>", n * 3 - 1),
              text_ref("step_#{n}_cmd", "<p>mix brando.setup</p>", n * 3)
            ]
          end)
    }
  end

  defp step_entry(n) do
    """
          <div class="step">
            <span class="label index">0#{n}</span>
            {% ref refs.step_#{n}_title %}
            {% ref refs.step_#{n}_text %}
            <span class="cmd">{% ref refs.step_#{n}_cmd %}</span>
          </div>\
    """
  end

  # Category and guide link are structural: they point at Brando's own
  # documentation, so they live in the markup rather than in editable refs.
  @cards [
    {"Content", "block_editor"},
    {"Schema", "blueprints"},
    {"Media", "media"},
    {"Workflow", "revisions"},
    {"Reach", "i18n"},
    {"Delivery", "deployment"}
  ]

  defp cards_module do
    %Content.Module{
      uid: @cards_uid,
      name: "Cards",
      namespace: "general",
      help_text: "A six-part grid. Each card carries a category, a title, a line of copy and a link.",
      class: "cards",
      code: """
      <section b-tpl="cards">
        <div class="inner">
          <div class="section-head">
            <span class="label">02 &mdash; What's in the box</span>
            {% ref refs.heading %}
            <span class="rule" aria-hidden="true"></span>
            <span class="note">Each links to its guide</span>
          </div>

          <div class="cards">
      #{@cards |> Enum.with_index(1) |> Enum.map_join("\n", &card_entry/1)}
          </div>
        </div>
      </section>
      """,
      sequence: 2,
      vars: [],
      refs:
        [header_ref("heading", 2, "Section heading", 0)] ++
          Enum.flat_map(1..6, fn n ->
            [
              header_ref("card_#{n}_title", 3, "Card #{n}", n * 2 - 1),
              text_ref("card_#{n}_text", "<p>Card description</p>", n * 2)
            ]
          end)
    }
  end

  defp card_entry({{category, guide}, n}) do
    """
          <a class="card" href="#{@docs_url}/#{guide}.html" target="_blank" rel="noopener">
            <span class="label">#{category}</span>
            {% ref refs.card_#{n}_title %}
            {% ref refs.card_#{n}_text %}
            <span class="go">#{guide} &rarr;</span>
          </a>\
    """
  end

  defp tips_module do
    %Content.Module{
      uid: @tips_uid,
      name: "Tips",
      namespace: "general",
      help_text: "Six short tips in two columns, each numbered.",
      class: "tips",
      code: """
      <section b-tpl="tips">
        <div class="inner">
          <div class="section-head">
            <span class="label">03 &mdash; Tips &amp; tricks</span>
            {% ref refs.heading %}
            <span class="rule" aria-hidden="true"></span>
          </div>

          <div class="tips">
      #{Enum.map_join(1..6, "\n", &tip_entry/1)}
          </div>
        </div>
      </section>
      """,
      sequence: 3,
      vars: [],
      refs:
        [header_ref("heading", 2, "Section heading", 0)] ++
          Enum.flat_map(1..6, fn n ->
            [
              header_ref("tip_#{n}_title", 3, "Tip #{n}", n * 2 - 1),
              text_ref("tip_#{n}_text", "<p>Tip description</p>", n * 2)
            ]
          end)
    }
  end

  defp tip_entry(n) do
    """
          <div class="tip">
            <span class="label index">0#{n}</span>
            <div class="body">
              {% ref refs.tip_#{n}_title %}
              {% ref refs.tip_#{n}_text %}
            </div>
          </div>\
    """
  end

  # The task table documents the framework rather than the site, so it is part
  # of the module markup. Names and descriptions track the tasks' own
  # @shortdoc lines; `plans?` marks the ones that show a diff before writing.
  @toolbox [
    {"Setup",
     [
       {"brando.install", "Install Brando into a Phoenix application", true},
       {"brando.setup", "Assets, database, superuser and seeds in one pass", false},
       {"brando.gen.seeds", "Seed default content for a new installation", false},
       {"brando.assets.setup", "Link the JS sources and build frontend assets", false}
     ]},
    {"Generate",
     [
       {"brando.gen.blueprint", "Define a new content type", true},
       {"brando.gen", "Schema, admin, forms and API from a blueprint", true},
       {"brando.gen.blueprint_migration", "A reversible migration and snapshot", true},
       {"brando.gen.admin", "Create another admin user", false},
       {"brando.gen.languages", "Identity and SEO rows for new languages", false},
       {"brando.gen.sitemap", "A CMS sitemap module", true}
     ]},
    {"Content",
     [
       {"brando.modules", "Export, plan and import module definitions", false},
       {"brando.entries.resave", "Re-render every entry after a template change", false},
       {"brando.identifiers.sync", "Repair missing or stale identifiers", false}
     ]},
    {"Ship",
     [
       {"brando.migrate", "Run public or tenant migrations", false},
       {"brando.static.build", "Build and digest static files", false},
       {"brando.static.deploy", "Upload static files to the CDN", false},
       {"brando.ssg", "Render the whole site to static files", false},
       {"brando.gen.release", "Release helpers and mix release config", true}
     ]},
    {"Upgrade",
     [
       {"brando.upgrade", "Apply versioned source upgrades", true},
       {"brando.migrate.55", "Move application source from 0.54 to 0.55", true}
     ]}
  ]

  defp terminal_module do
    %Content.Module{
      uid: @terminal_uid,
      name: "Toolbox",
      namespace: "general",
      help_text:
        "A shell listing the mix tasks Brando adds, with instructions alongside it. " <>
          "The task table is part of the markup so it stays accurate; the prose is editable.",
      class: "terminal",
      code: """
      <section b-tpl="terminal">
        <div class="inner">
          <div class="section-head">
            <span class="label">04 &mdash; The toolbox</span>
            {% ref refs.heading %}
            <span class="rule" aria-hidden="true"></span>
            <span class="note">Run any of these in this directory</span>
          </div>

          <div class="intro">{% ref refs.intro %}</div>

          <div class="layout">
            <div class="shell">
              <div class="bar">
                <i aria-hidden="true"></i><i aria-hidden="true"></i><i aria-hidden="true"></i>
                <span class="path">~ &mdash; zsh</span>
                <span class="badge label"><span class="dot" aria-hidden="true"></span> Brando #{brando_version()}</span>
              </div>

              <div class="output">
                <div class="prompt"><span class="sigil">$</span> mix help brando</div>
      #{Enum.map_join(@toolbox, "\n", &toolbox_group/1)}

                <div class="group">
                  <div class="comment"># #{toolbox_count()} shown &middot; run `mix help --search brando.` for the rest</div>
                  <div class="prompt"><span class="sigil">$</span> <span class="caret" aria-hidden="true"></span></div>
                </div>
              </div>

              <div class="foot">
                <span><span class="key">&#8633;</span> complete</span>
                <span><span class="key">&#9166;</span> run</span>
                <span><span class="key">--help</span> options for any task</span>
                <span class="env">elixir #{System.version()} &middot; otp #{System.otp_release()}</span>
              </div>
            </div>

            <aside class="rail">
      #{Enum.map_join(1..4, "\n", &rail_entry/1)}
              <p class="legend">
                <span class="starred">&#9733;</span> shows a diff first<br>
                &rarr; full list: mix help --search brando.
              </p>
            </aside>
          </div>
        </div>
      </section>
      """,
      sequence: 4,
      vars: [],
      refs:
        [
          header_ref("heading", 2, "Section heading", 0),
          text_ref("intro", "<p>Introduction</p>", 1)
        ] ++
          Enum.flat_map(1..4, fn n ->
            [
              header_ref("rail_#{n}_title", 3, "Note #{n}", n * 2),
              text_ref("rail_#{n}_text", "<p>Note description</p>", n * 2 + 1)
            ]
          end)
    }
  end

  defp toolbox_group({name, tasks}) do
    rows = Enum.map_join(tasks, "\n", &toolbox_task/1)

    """
                <div class="group">
                  <div class="group-name">#{name} <span class="rule" aria-hidden="true"></span></div>
      #{rows}
                </div>\
    """
  end

  defp toolbox_task({name, description, plans?}) do
    # Dots are dimmed so the eye reads the task's last segment first.
    punctuated = String.replace(name, ".", ~s(<span class="punct">.</span>))
    classes = if plans?, do: "task plans", else: "task"

    ~s(            <div class="#{classes}"><span class="name">#{punctuated}</span><span class="desc">#{description}</span></div>)
  end

  defp toolbox_count, do: @toolbox |> Enum.flat_map(&elem(&1, 1)) |> length()

  defp rail_entry(n) do
    """
              <div class="item">
                {% ref refs.rail_#{n}_title %}
                {% ref refs.rail_#{n}_text %}
              </div>\
    """
  end

  defp closing_module do
    %Content.Module{
      uid: @closing_uid,
      name: "Closing",
      namespace: "general",
      help_text: "The last word on a page: a heading, a line of copy and one link.",
      class: "closing",
      code: """
      <section b-tpl="closing">
        <div class="inner">
          <div class="row">
            <div class="copy">
              <span class="label">05 &mdash; Last thing</span>
              {% ref refs.title %}
              {% ref refs.text %}
            </div>
            <a class="button" href="/admin/pages">Go to Pages</a>
          </div>
        </div>
      </section>
      """,
      sequence: 5,
      vars: [],
      refs: [
        header_ref("title", 2, "Closing heading", 0),
        text_ref("text", "<p>Closing paragraph</p>", 1)
      ]
    }
  end

  defp footer_module do
    %Content.Module{
      uid: @footer_uid,
      name: "Footer",
      namespace: "general",
      help_text: "Footer fragment: a line of copy beside link columns.",
      class: "footer",
      code: """
      <div b-tpl="footer">
        <div class="fragment">{% ref refs.text %}</div>
        <div class="lists">
          <div>
            <h5>Guides</h5>
            <ul>
              <li><a href="#{@docs_url}/overview.html">Overview</a></li>
              <li><a href="#{@docs_url}/blueprints.html">Blueprints</a></li>
              <li><a href="#{@docs_url}/block_editor.html">Block editor</a></li>
              <li><a href="#{@docs_url}/deployment.html">Deployment</a></li>
            </ul>
          </div>
          <div>
            <h5>Content</h5>
            <ul>
              <li><a href="/admin/pages">Pages</a></li>
              <li><a href="/admin/pages/fragments">Fragments</a></li>
              <li><a href="/admin/navigation">Navigation</a></li>
              <li><a href="/admin/config/identity">Identity &amp; SEO</a></li>
            </ul>
          </div>
        </div>
      </div>
      """,
      sequence: 6,
      vars: [],
      refs: [text_ref("text", "<p>Footer text</p>", 0)]
    }
  end

  defp brando_version do
    case :application.get_key(:brando, :vsn) do
      {:ok, vsn} -> vsn |> to_string() |> String.split("-") |> hd()
      _ -> ""
    end
  end

  # ── Refs ──────────────────────────────────────────────────────────────────

  defp header_ref(name, level, text, sequence) do
    %Content.Ref{
      name: name,
      uid: Brando.Utils.generate_uid(),
      description: "",
      sequence: sequence,
      data: %HeaderBlock{
        type: "header",
        data: %HeaderBlock.Data{level: level, text: text, class: nil, id: nil}
      }
    }
  end

  # Text block content is tiptap HTML, so paragraphs arrive wrapped in `<p>`
  # exactly as the editor would save them.
  defp text_ref(name, text, sequence) do
    %Content.Ref{
      name: name,
      uid: Brando.Utils.generate_uid(),
      description: "",
      sequence: sequence,
      data: %TextBlock{
        type: "text",
        data: %TextBlock.Data{type: "paragraph", text: text, extensions: []}
      }
    }
  end

  # ── The index page ────────────────────────────────────────────────────────

  defp index_page(language, user, modules) do
    if Brando.Repo.get_by(Pages.Page, uri: "index", language: language) do
      :exists
    else
      page =
        Brando.Repo.insert!(%Pages.Page{
          creator_id: user.id,
          title: "Index",
          uri: "index",
          language: language,
          template: "index.html",
          status: :published,
          is_homepage: true,
          sequence: 0,
          entry_blocks: [
            module_block(modules.hero, 0, hero_content()),
            module_block(modules.steps, 1, steps_content()),
            module_block(modules.cards, 2, cards_content()),
            module_block(modules.tips, 3, tips_content()),
            module_block(modules.terminal, 4, terminal_content()),
            module_block(modules.closing, 5, closing_content())
          ]
        })

      footer_fragment(page, language, user, modules)

      # Repo inserts bypass context rendering callbacks. Render here so the page
      # is usable on its first request, before any rendering worker has run.
      {:ok, page} = Content.Blocks.render_entry(Pages.Page, page.id)
      page
    end
  end

  defp hero_content do
    ledger = [
      {"One", "page, published at /"},
      {"Six", "blocks on this page"},
      {"Seven", "modules you can edit"},
      {"One", "menu, under Navigation"}
    ]

    [
      text_ref("eyebrow", "<p>Brando #{brando_version()} — installed</p>", 0),
      header_ref(
        "title",
        1,
        "Your site is up.\n<span class=\"soft\">Now make it yours.</span>",
        1
      ),
      text_ref(
        "lead",
        "<p>Every word on this page is content, not template. It was seeded by " <>
          "<code>mix brando.setup</code> — six blocks, seven modules and a footer fragment, " <>
          "all of which you can rewrite, reorder or delete from the admin.</p>",
        2
      )
    ] ++
      (ledger
       |> Enum.with_index(1)
       |> Enum.flat_map(fn {{value, label}, n} ->
         [
           text_ref("ledger_#{n}_value", "<p>#{value}</p>", 2 + n * 2 - 1),
           text_ref("ledger_#{n}_label", "<p>#{label}</p>", 2 + n * 2)
         ]
       end))
  end

  defp steps_content do
    steps = [
      {"Edit this page", "Pages → Index holds the blocks you're reading. Change a heading, save, reload.",
       "/admin/pages"},
      {"Write a module", "Your markup, with named refs the editor fills in. You keep the HTML.", "{% ref refs.title %}"},
      {"Model your data", "A blueprint gives you schema, migration, admin forms and listings at once.", "mix brando.gen"}
    ]

    [header_ref("heading", 2, "Three moves to your own page.", 0)] ++
      (steps
       |> Enum.with_index(1)
       |> Enum.flat_map(fn {{title, text, cmd}, n} ->
         [
           header_ref("step_#{n}_title", 3, title, n * 3 - 2),
           text_ref("step_#{n}_text", "<p>#{text}</p>", n * 3 - 1),
           text_ref("step_#{n}_cmd", "<p>#{escape(cmd)}</p>", n * 3)
         ]
       end))
  end

  defp cards_content do
    cards = [
      {"Block editor", "Modules, multi-blocks, containers and live preview of your real templates."},
      {"Blueprints", "One definition becomes the schema, migration, admin forms and listings."},
      {"Images &amp; files", "Focal points, generated sizes, CDN delivery and lazy-loaded srcsets."},
      {"Revisions", "Every save is kept. Schedule publishing ahead, roll back whenever."},
      {"i18n &amp; SEO", "Per-language content, identity, meta, JSON-LD and generated sitemaps."},
      {"Static export", "Render the whole site to files and deploy it anywhere you like."}
    ]

    [header_ref("heading", 2, "Everything you just installed.", 0)] ++
      (cards
       |> Enum.with_index(1)
       |> Enum.flat_map(fn {{title, text}, n} ->
         [
           header_ref("card_#{n}_title", 3, title, n * 2 - 1),
           text_ref("card_#{n}_text", "<p>#{text}</p>", n * 2)
         ]
       end))
  end

  defp tips_content do
    tips = [
      {"Live preview as you type",
       "Wire up <code>LivePreview</code> and the editor renders your real templates while editing."},
      {"Setup is idempotent", "<code>mix brando.setup</code> skips every step whose result already exists."},
      {"Modules are portable", "Export them as JSON and import them into the next project."},
      {"Own the markup", "Change how any block renders in <code>villain/parser.ex</code>."},
      {"Menus are content", "The navigation above lives under Navigation, never in a template."},
      {"Design tokens, not guesses", "<code>@space</code> and <code>@column</code> come straight from your artboard."}
    ]

    [header_ref("heading", 2, "Easy to miss on day one.", 0)] ++
      (tips
       |> Enum.with_index(1)
       |> Enum.flat_map(fn {{title, text}, n} ->
         [
           header_ref("tip_#{n}_title", 3, title, n * 2 - 1),
           text_ref("tip_#{n}_text", "<p>#{text}</p>", n * 2)
         ]
       end))
  end

  defp terminal_content do
    rail = [
      {"Nothing writes blindly",
       "Starred tasks build an Igniter plan, print the diff and wait. Answer <code>n</code> and nothing touched your source."},
      {"Start with a blueprint",
       "Describe the content type once; <code>mix brando.gen</code> turns it into schema, admin and API."},
      {"Rerunning is safe",
       "<code>brando.setup</code> skips any step whose result already exists, so it is fine to run it twice."},
      {"After a template change",
       "<code>brando.entries.resave</code> re-renders stored content so the new markup reaches published pages."}
    ]

    [
      header_ref("heading", 2, "Everything Brando adds to mix.", 0),
      text_ref(
        "intro",
        "<p>Brando ships around forty mix tasks. These are the ones you will actually reach for. " <>
          "Anything marked <span class=\"starred\">★</span> writes a reviewable plan first — it shows you " <>
          "the diff and waits for you to accept it. Add <code>--help</code> to any task for its full options.</p>",
        1
      )
    ] ++
      (rail
       |> Enum.with_index(1)
       |> Enum.flat_map(fn {{title, text}, n} ->
         [
           header_ref("rail_#{n}_title", 3, title, n * 2),
           text_ref("rail_#{n}_text", "<p>#{text}</p>", n * 2 + 1)
         ]
       end))
  end

  defp closing_content do
    [
      header_ref("title", 2, "When this page has served its purpose, delete it.", 0),
      text_ref(
        "text",
        "<p>Nothing here is special. It is a page, seven modules and a fragment — all removable " <>
          "from the admin, none of it wired into your templates.</p>",
        1
      )
    ]
  end

  # Ref content is parsed for Liquid on its way into the module markup, so a
  # command that shows a `{% ref %}` tag has to arrive with its braces escaped
  # or the renderer consumes it as a tag of its own.
  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace("{", "&#123;")
    |> String.replace("}", "&#125;")
  end

  defp module_block(module, sequence, refs) do
    %Pages.Page.Blocks{
      sequence: sequence,
      block: %Content.Block{
        type: :module,
        uid: Brando.Utils.generate_uid(),
        module_id: module.id,
        source: Pages.Page.Blocks,
        multi: false,
        sequence: sequence,
        vars: [],
        refs: refs
      }
    }
  end

  defp footer_fragment(page, language, user, modules) do
    fragment =
      Brando.Repo.insert!(%Pages.Fragment{
        parent_key: "partials",
        key: "footer",
        title: "Footer",
        language: language,
        page_id: page.id,
        creator_id: user.id,
        entry_blocks: [
          %Pages.Fragment.Blocks{
            sequence: 0,
            block: %Content.Block{
              type: :module,
              uid: Brando.Utils.generate_uid(),
              module_id: modules.footer.id,
              source: Pages.Fragment.Blocks,
              multi: false,
              sequence: 0,
              vars: [],
              refs: [
                text_ref(
                  "text",
                  "<p>This footer is a page fragment. Edit it under Pages → Fragments, " <>
                    "or remove it from the layout.</p>",
                  0
                )
              ]
            }
          }
        ]
      })

    {:ok, fragment} = Content.Blocks.render_entry(Pages.Fragment, fragment.id)
    fragment
  end

  defp site_name do
    case Brando.config(:app_name) do
      name when is_binary(name) -> name
      _ -> "Brando"
    end
  end
end

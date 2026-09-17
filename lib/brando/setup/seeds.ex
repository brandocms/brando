defmodule Brando.Setup.Seeds do
  @moduledoc """
  Default content for a freshly installed application.

  Creates the content a new site needs before its first request succeeds:
  identity and SEO per configured language, a small set of modules, a published
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
  @text_uid "brando-default-text"
  @columns_uid "brando-default-columns"

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
                %{
                  key: "home",
                  status: :published,
                  sequence: 0,
                  link: %{
                    type: :link,
                    key: "link",
                    label: "Link",
                    link_type: :url,
                    link_text: "Home",
                    value: "/"
                  }
                }
              ]
            },
            user
          )

        menu
    end
  end

  # Modules are global, so they are seeded once regardless of language. Their
  # uid carries module identity across imports and upgrades, so a stable uid is
  # what makes a rerun a no-op instead of a duplicate.
  defp modules(user) do
    %{
      hero:
        upsert_module(@hero_uid, user, fn ->
          %Content.Module{
            uid: @hero_uid,
            name: "Hero",
            namespace: "general",
            help_text: "Page introduction with a heading and a lead paragraph",
            class: "hero",
            code: """
            <section b-tpl="hero">
              <div class="inner">
                {% ref refs.title %}
                <div class="lead">{% ref refs.lead %}</div>
              </div>
            </section>
            """,
            sequence: 0,
            vars: [],
            refs: [
              header_ref("title", 1, "Heading", 0),
              text_ref("lead", "<p>Lead paragraph</p>", 1)
            ]
          }
        end),
      text:
        upsert_module(@text_uid, user, fn ->
          %Content.Module{
            uid: @text_uid,
            name: "Text",
            namespace: "general",
            help_text: "A section of rich text",
            class: "text",
            code: """
            <section b-tpl="text">
              <div class="inner">
                {% ref refs.text %}
              </div>
            </section>
            """,
            sequence: 1,
            vars: [],
            refs: [text_ref("text", "<p>Text</p>", 0)]
          }
        end),
      columns:
        upsert_module(@columns_uid, user, fn ->
          %Content.Module{
            uid: @columns_uid,
            name: "Columns",
            namespace: "general",
            help_text: "Three columns, each with a heading and a paragraph",
            class: "columns",
            code: """
            <section b-tpl="columns">
              <div class="inner">
                <div class="column">
                  {% ref refs.first_title %}
                  {% ref refs.first_text %}
                </div>
                <div class="column">
                  {% ref refs.second_title %}
                  {% ref refs.second_text %}
                </div>
                <div class="column">
                  {% ref refs.third_title %}
                  {% ref refs.third_text %}
                </div>
              </div>
            </section>
            """,
            sequence: 2,
            vars: [],
            refs: [
              header_ref("first_title", 2, "First heading", 0),
              text_ref("first_text", "<p>First paragraph</p>", 1),
              header_ref("second_title", 2, "Second heading", 2),
              text_ref("second_text", "<p>Second paragraph</p>", 3),
              header_ref("third_title", 2, "Third heading", 4),
              text_ref("third_text", "<p>Third paragraph</p>", 5)
            ]
          }
        end)
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
            module_block(modules.hero, 0, [
              header_ref("title", 1, site_name(), 0),
              text_ref(
                "lead",
                "<p>Your site is running on Brando. This page was seeded by " <>
                  "<code>mix brando.setup</code> — every section below is a block you can " <>
                  "edit, reorder or delete in the admin.</p>",
                1
              )
            ]),
            module_block(modules.text, 1, [
              text_ref(
                "text",
                "<p>Sign in at <a href=\"/admin\">/admin</a> with the account you just created, " <>
                  "then replace this page's content with your own.</p>" <>
                  "<p>Each section here is a module: a small template with named refs that " <>
                  "editors fill in. Build the modules your design needs, and delete these.</p>",
                0
              )
            ]),
            module_block(modules.columns, 2, [
              header_ref("first_title", 2, "Pages", 0),
              text_ref(
                "first_text",
                "<p>Pages are composed of blocks. Open this page under Pages to see the three " <>
                  "blocks that make it up, and add another from the module picker.</p>",
                1
              ),
              header_ref("second_title", 2, "Modules", 2),
              text_ref(
                "second_text",
                "<p>The Hero, Text and Columns modules rendering this page live under " <>
                  "Configuration → Modules, with their markup and refs.</p>",
                3
              ),
              header_ref("third_title", 2, "Navigation", 4),
              text_ref(
                "third_text",
                "<p>The menu above is under Navigation. Menus and their items are content " <>
                  "too, so they are edited rather than written into templates.</p>",
                5
              )
            ])
          ]
        })

      footer_fragment(page, language, user, modules)

      # Repo inserts bypass context rendering callbacks. Render here so the page
      # is usable on its first request, before any rendering worker has run.
      {:ok, page} = Content.Blocks.render_entry(Pages.Page, page.id)
      page
    end
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
              module_id: modules.text.id,
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

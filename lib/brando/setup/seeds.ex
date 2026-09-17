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

  defp identity(language) do
    case Sites.get_identity(%{matches: %{language: language}}) do
      {:ok, _identity} -> :exists
      {:error, _} -> Sites.create_default_identity(language)
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
            <section b-tpl="hero" class="hero">
              <div class="inner">
                {% ref refs.title %}
                {% ref refs.lead %}
              </div>
            </section>
            """,
            sequence: 0,
            vars: [],
            refs: [
              header_ref("title", 1, "Heading", 0),
              text_ref("lead", "Lead paragraph", 1)
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
            <section b-tpl="text" class="text">
              <div class="inner">
                {% ref refs.text %}
              </div>
            </section>
            """,
            sequence: 1,
            vars: [],
            refs: [text_ref("text", "Text", 0)]
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
              header_ref("title", 1, "Welcome to #{site_name()}", 0),
              text_ref(
                "lead",
                "This page was created by <code>mix brando.setup</code>. Edit it in the admin, or replace it with your own content.",
                1
              )
            ]),
            module_block(modules.text, 1, [
              text_ref(
                "text",
                "Sign in at <a href=\"/admin\">/admin</a> to edit pages, modules and navigation.",
                0
              )
            ])
          ]
        })

      footer_fragment(page, language, user)

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

  defp footer_fragment(page, language, user) do
    Brando.Repo.insert!(%Pages.Fragment{
      parent_key: "partials",
      key: "footer",
      title: "Footer",
      language: language,
      entry_blocks: [],
      page_id: page.id,
      creator_id: user.id
    })
  end

  defp site_name do
    case Brando.config(:app_name) do
      name when is_binary(name) -> name
      _ -> "Brando"
    end
  end
end

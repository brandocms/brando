defmodule E2E.MarkdownProvider do
  @moduledoc false
  alias Brando.MarkdownSources.{Source, Version}
  alias Brando.Repo

  def fetch(_, source) do
    version = source.id |> Brando.MarkdownSources.versions() |> hd()
    {:ok, Map.take(version, [:commit, :markdown, :repository, :path])}
  end

  def advance(user, commit, title) do
    source = Brando.MarkdownSources.list_sources() |> Enum.find(&(&1.connection == "e2e-docs"))

    document = %{
      commit: String.duplicate(commit, 40),
      markdown: "# #{title} guide",
      repository: "brando-e2e/docs",
      path: source.path
    }

    {:ok, html} = Brando.MarkdownSources.Renderer.render(document)

    Repo.insert!(
      struct(
        Version,
        Map.merge(document, %{
          source_id: source.id,
          html: html,
          content_hash: :crypto.hash(:sha256, html) |> Base.encode16(case: :lower)
        })
      )
    )

    user
  end

  def setup(user) do
    source =
      Repo.insert!(%Source{
        name: "Installation guide",
        connection: "e2e-docs",
        ref: "refs/heads/main",
        path: "guides/install.md"
      })

    versions =
      for {commit, markdown} <- [
            {"a", "# First guide\n\nPublished instructions."},
            {"b", "# Second guide\n\nUpdated instructions."}
          ] do
        document = %{
          commit: String.duplicate(commit, 40),
          markdown: markdown,
          repository: "brando-e2e/docs",
          path: source.path
        }

        {:ok, html} = Brando.MarkdownSources.Renderer.render(document)

        Repo.insert!(
          struct(
            Version,
            Map.merge(document, %{
              source_id: source.id,
              html: html,
              content_hash: :crypto.hash(:sha256, html) |> Base.encode16(case: :lower)
            })
          )
        )
      end

    source |> Ecto.Changeset.change(latest_version_id: hd(versions).id, publication_status: "Rendered") |> Repo.update!()

    module =
      Repo.insert!(%Brando.Content.Module{
        type: :liquid,
        uid: Ecto.UUID.generate(),
        name: %{"en" => "Repository document", "no" => "Repository document"},
        namespace: %{"en" => "05 LIVE PREVIEW TEST", "no" => "05 LIVE PREVIEW TEST"},
        help_text: %{"en" => "A connected Markdown document"},
        class: "repository-document",
        multi: false,
        datasource: false,
        code: "{% ref refs.document %}",
        refs: [
          %Brando.Content.Ref{
            name: "document",
            description: "Repository document",
            uid: Brando.Utils.generate_uid(),
            data: %Brando.Villain.Blocks.MarkdownSourceBlock{data: %Brando.Villain.Blocks.MarkdownSourceBlock.Data{}}
          }
        ]
      })

    Brando.Cache.Query.evict_schema(Brando.Content.Module)
    Brando.Content.fetch_module(module.id)
    user
  end
end

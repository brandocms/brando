defmodule BrandoAdmin.MarkdownSourcesTest do
  use Brando.LiveCase

  setup do
    old = Application.get_env(:brando, :markdown_sources)

    Application.put_env(:brando, :markdown_sources,
      connections: %{
        "docs" => %{secret: String.duplicate("s", 40), repository: "acme/docs", repository_id: 42, destinations: [nil]}
      }
    )

    on_exit(fn ->
      if old,
        do: Application.put_env(:brando, :markdown_sources, old),
        else: Application.delete_env(:brando, :markdown_sources)
    end)

    :ok
  end

  test "missing connections explain developer setup and disable the form", %{conn: conn} do
    Application.put_env(:brando, :markdown_sources, connections: %{})
    {:ok, view, html} = live(conn, "/admin/config/markdown-sources")
    assert html =~ "A developer needs to connect your repository"
    assert html =~ "runtime.exs"
    assert has_element?(view, "#markdown-source-form fieldset[disabled]")
  end

  test "folder additions skip existing sources and roll back invalid selections", %{current_user: user} do
    assert {:ok, 2} =
             Brando.MarkdownSources.add_documents(
               "docs",
               "refs/heads/main",
               ["guides/start.md", "guides/install.md"],
               user
             )

    assert {:ok, 0} =
             Brando.MarkdownSources.add_documents(
               "docs",
               "refs/heads/main",
               ["guides/start.md", "guides/install.md"],
               user
             )

    assert {:error, _} =
             Brando.MarkdownSources.add_documents("docs", "refs/heads/main", ["guides/new.md", "../invalid.md"], user)

    assert length(Brando.MarkdownSources.list_sources()) == 2
    assert {:error, _} = Brando.MarkdownSources.add_documents("missing", "refs/heads/main", ["guides/other.md"], user)
  end

  test "source manager saves, reloads, validates paths, and enqueues manual recovery", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/config/markdown-sources")

    html =
      view
      |> form("#markdown-source-form",
        source: %{
          name: "Installation guide",
          connection: "docs",
          ref: "refs/heads/main",
          path: "guides/install.md",
          enabled: "true"
        }
      )
      |> render_submit()

    assert html =~ "Source saved"
    assert [source] = Brando.MarkdownSources.list_sources()
    assert source.path == "guides/install.md"

    html =
      view
      |> form("#markdown-source-form",
        source: %{
          name: "Installation guide",
          connection: "docs",
          ref: "refs/heads/main",
          path: "../secrets.md",
          enabled: "true"
        }
      )
      |> render_submit()

    assert html =~ "repository-relative Markdown file"

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert view |> element("#markdown-source-#{source.id} button", "Refresh from GitHub") |> render_click() =~
               "Refresh queued"
    end)
  end
end

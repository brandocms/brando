defmodule Brando.MarkdownOffTest.Entry do
  # What `enabled?/1` reads off a blueprint with blocks, a URL and
  # `trait :meta, markdown: false`.
  def __trait__(Brando.Trait.Meta), do: [markdown: Process.get(:markdown_option, false)]
  def __trait__(_), do: false
  def has_trait(Brando.Trait.Blocks), do: true
  def has_trait(_), do: false
  def __blocks_fields__, do: [%{name: :blocks}]
  def __absolute_url__(_entry), do: "/entries/1"
end

defmodule Brando.Plug.MarkdownTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Brando.Factory
  alias Brando.Pages

  doctest Brando.Plug.Markdown
  doctest Brando.SEO.Markdown

  # A site's endpoint and page controller, cut down: the plug, then a
  # controller that loads published pages by URI as the real ones do.
  defmodule Site do
    use Plug.Builder

    plug Brando.Plug.Markdown
    plug :controller

    def controller(%{path_info: ["listing"]} = conn, _), do: html(conn, "<p>A listing, not an entry</p>")
    def controller(%{path_info: ["admin" | _]} = conn, _), do: html(conn, "<p>admin</p>")

    def controller(%{path_info: [uri]} = conn, _) do
      case Pages.get_page(%{matches: %{uri: uri, language: "en"}, status: :published, preload: [:alternate_entries]}) do
        {:ok, page} -> conn |> Brando.Plug.HTML.put_hreflang(page) |> html("<h1>#{page.title}</h1>")
        {:error, _} -> conn |> send_resp(404, "Not found page") |> halt()
      end
    end

    def controller(conn, _), do: conn |> send_resp(404, "Not found page") |> halt()

    defp html(conn, body), do: conn |> put_resp_content_type("text/html") |> send_resp(200, body) |> halt()
  end

  setup do
    user = Factory.insert(:random_user)

    module_params =
      Factory.params_for(:module, %{
        code: ~s(<div class="text">{% ref refs.text %}</div>),
        refs: [
          %{
            name: "text",
            description: nil,
            uid: Brando.Utils.generate_uid(),
            data: %{type: "text", data: %{text: "Default", type: "paragraph"}}
          }
        ],
        vars: []
      })

    {:ok, module} = Brando.Content.create_module(module_params, user)
    {:ok, %{user: user, module: module}}
  end

  defp page!(attrs, module, user) do
    text = %Brando.Villain.Blocks.TextBlock{
      data: %Brando.Villain.Blocks.TextBlock.Data{
        text: "<p>We restore <strong>bathhouses</strong>.</p>",
        type: :paragraph
      }
    }

    block = %Brando.Content.Block{
      type: :module,
      active: true,
      source: Brando.Pages.Page.Blocks,
      module_id: module.id,
      uid: Brando.Utils.generate_uid(),
      creator_id: user.id,
      refs: [%Brando.Content.Ref{name: "text", uid: Brando.Utils.generate_uid(), data: text}]
    }

    attrs =
      Map.merge(
        %{
          title: "About",
          uri: "about",
          status: :published,
          creator: user,
          entry_blocks: [%Brando.Pages.Page.Blocks{sequence: 0, block: block}]
        },
        attrs
      )

    Factory.insert(:page, Map.to_list(attrs))
  end

  defp request(path, headers \\ []) do
    conn = Enum.reduce(headers, Plug.Test.conn(:get, path), fn {k, v}, conn -> Plug.Conn.put_req_header(conn, k, v) end)
    Site.call(conn, Site.init([]))
  end

  test "an entry's URL with .md gives its Markdown", %{module: module, user: user} do
    page = page!(%{}, module, user)

    conn = request("/about.md")

    assert conn.status == 200
    assert conn.resp_body == "# About\n\nWe restore **bathhouses**.\n"
    assert ["text/markdown" <> _] = Plug.Conn.get_resp_header(conn, "content-type")
    assert Plug.Conn.get_resp_header(conn, "vary") == ["Accept"]

    assert Plug.Conn.get_resp_header(conn, "link") == [
             ~s(<#{Brando.Blueprint.URL.resolve(page, :with_host)}>; rel="canonical")
           ]

    [etag] = Plug.Conn.get_resp_header(conn, "etag")
    again = request("/about.md", [{"if-none-match", etag}])
    assert again.status == 304
    assert again.resp_body == ""
  end

  test "Accept: text/markdown on the normal URL gives Markdown, HTML says it varies", %{module: module, user: user} do
    page!(%{}, module, user)

    markdown = request("/about", [{"accept", "text/markdown"}])
    assert markdown.resp_body =~ "# About"
    assert ["text/markdown" <> _] = Plug.Conn.get_resp_header(markdown, "content-type")

    html = request("/about", [{"accept", "text/html,application/xhtml+xml,*/*;q=0.8"}])
    assert html.resp_body == "<h1>About</h1>"
    assert Plug.Conn.get_resp_header(html, "vary") == ["Accept"]
  end

  test "drafts, scheduled and deleted entries are not found", %{module: module, user: user} do
    page!(%{uri: "draft", status: :draft}, module, user)
    later = page!(%{uri: "later"}, module, user)

    # Published, but not until later: the page controller should not have
    # loaded it, and the Markdown does not trust that it did.
    Brando.Repo.update_all(Ecto.Query.from(p in Brando.Pages.Page, where: p.id == ^later.id),
      set: [publish_at: DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)]
    )

    assert request("/draft.md").status == 404
    assert request("/later.md").status == 404
    assert request("/missing.md").status == 404

    # Asked for by Accept, the page's own answer stands.
    assert request("/draft", [{"accept", "text/markdown"}]).resp_body == "Not found page"
  end

  test "a page that is not an entry has no Markdown version" do
    conn = request("/listing.md")
    assert conn.status == 404
    assert conn.resp_body == "Not found\n"

    # Its HTML does not vary by Accept.
    assert Plug.Conn.get_resp_header(request("/listing"), "vary") == []
  end

  test "excluded paths and other methods are left alone" do
    conn = request("/admin/notes.md")
    assert conn.resp_body == "<p>admin</p>"

    post = Site.call(Plug.Test.conn(:post, "/about.md"), Site.init([]))
    assert post.resp_body == "Not found page"
  end

  test "the page head names the Markdown version", %{module: module, user: user} do
    page = page!(%{}, module, user)
    {:ok, page} = Pages.get_page(%{matches: %{id: page.id}, preload: [:alternate_entries]})

    conn = Brando.Plug.HTML.put_hreflang(%Plug.Conn{assigns: %{language: "en"}}, page)
    assigns = %{conn: conn}
    html = rendered_to_string(~H"<Brando.HTML.render_hreflangs conn={@conn} />")

    assert html =~ ~s(<link rel="alternate" type="text/markdown" href="#{Brando.SEO.Markdown.url(page)}">)
    assert Brando.SEO.Markdown.url(page) =~ ~r/\/about\.md$/
  end

  test "a blueprint can turn its Markdown version off" do
    assert Brando.SEO.Markdown.enabled?(Brando.Pages.Page)
    refute Brando.SEO.Markdown.enabled?(Brando.Sites.SEO)
    refute Brando.SEO.Markdown.enabled?(Brando.MarkdownOffTest.Entry)

    Process.put(:markdown_option, true)
    assert Brando.SEO.Markdown.enabled?(Brando.MarkdownOffTest.Entry)
  end
end

defmodule Mix.Tasks.Brando.Migrate54TemplatesTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate54

  @navigation_path "lib/lett_web/components/partials/navigation.html.heex"

  test "rewrites navigation item reads inside a generator over the navigation's items" do
    navigation = """
    <section class="main">
      <ul>
        <%= for item <- @navigation.items do %>
          <%= if item.status == :published do %>
            <li>
              <a class={Brando.HTML.active(@conn, "\#{item.url}/*")} href={item.url}>
                <%= item.title %>
              </a>
            </li>
          <% end %>
        <% end %>
      </ul>
    </section>
    """

    igniter = migrate(%{@navigation_path => navigation})

    assert source(igniter, @navigation_path) == """
           <section class="main">
             <ul>
               <%= for item <- @navigation.items do %>
                 <%= if item.status == :published do %>
                   <li>
                     <a class={Brando.HTML.active(@conn, "\#{Brando.HTML.get_menu_item_url(item)}/*")} href={Brando.HTML.get_menu_item_url(item)}>
                       <%= Brando.HTML.get_menu_item_text(item) %>
                     </a>
                   </li>
                 <% end %>
               <% end %>
             </ul>
           </section>
           """

    refute Enum.any?(igniter.warnings, &(&1 =~ "Navigation items"))

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate54.igniter()
    assert_unchanged(rerun, [@navigation_path])
  end

  test "rewrites :for item reads, sub-items and their reads" do
    navigation = """
    <li :for={item <- @menu.items}>
      <a href={item.url} target={item.open_in_new_window && "_blank"}>{item.title}</a>
      <ul :if={item.items != []}>
        <li :for={child <- item.items}><a href={child.url}>{child.title}</a></li>
      </ul>
    </li>
    """

    igniter = migrate(%{@navigation_path => navigation})

    assert source(igniter, @navigation_path) == """
           <li :for={item <- @menu.items}>
             <a href={Brando.HTML.get_menu_item_url(item)} target={Brando.HTML.get_menu_item_target_blank(item) && "_blank"}>{Brando.HTML.get_menu_item_text(item)}</a>
             <ul :if={item.children != []}>
               <li :for={child <- item.children}><a href={Brando.HTML.get_menu_item_url(child)}>{Brando.HTML.get_menu_item_text(child)}</a></li>
             </ul>
           </li>
           """
  end

  test "lists navigation item reads it cannot tell apart from other data" do
    navigation = """
    <a :for={item <- @navigation.items} href={item.url}>{item.title}</a>
    <a :for={item <- @products} href={item.url}>{item.title}</a>
    """

    in_text = """
    <%= for item <- @navigation.items do %>
      <p>Link: item.url</p><a href={item.url}></a>
    <% end %>
    """

    text_path = "lib/lett_web/components/partials/footer.html.heex"
    igniter = migrate(%{@navigation_path => navigation, text_path => in_text})

    assert_unchanged(igniter, [@navigation_path])

    assert source(igniter, text_path) == """
           <%= for item <- @navigation.items do %>
             <p>Link: item.url</p><a href={Brando.HTML.get_menu_item_url(item)}></a>
           <% end %>
           """

    assert_has_warning(igniter, fn warning ->
      warning =~ "Navigation items" and
        warning =~ "#{@navigation_path}:1: <a :for={item <- @navigation.items} href={item.url}>" and
        warning =~ "#{text_path}:2: <p>Link: item.url</p>"
    end)
  end

  test "lists navigation reads when the file binds the name in a pattern elsewhere" do
    for other <- [
          "<p :for={{item, index} <- Enum.with_index(@products)}>{index}: {item.title}</p>",
          "<%= with %{product: item} = @featured do %><%= item.title %><% end %>",
          "<%= Enum.map(@products, fn {item, _} -> item.title end) %>",
          "<%= case @featured do %><% {:ok, item} -> %><%= item.title %><% end %>"
        ] do
      navigation = """
      <a :for={item <- @navigation.items} href={item.url}>{item.title}</a>
      #{other}
      """

      igniter = migrate(%{@navigation_path => navigation})

      assert_unchanged(igniter, [@navigation_path])
      assert_has_warning(igniter, &(&1 =~ "Navigation items" and &1 =~ "#{@navigation_path}:1:"))
    end
  end

  test "only lists item reads when the application has a schema of its own with items" do
    navigation = """
    <li :for={dish <- @menu.items}>{dish.title}</li>
    """

    schema = """
    defmodule Lett.Restaurant.Menu do
      use Ecto.Schema

      schema "menus" do
        has_many :items, Lett.Restaurant.Dish
      end
    end
    """

    igniter = migrate(%{@navigation_path => navigation, "lib/lett/restaurant/menu.ex" => schema})

    assert_unchanged(igniter, [@navigation_path])
    assert_has_warning(igniter, &(&1 =~ "Navigation items" and &1 =~ "#{@navigation_path}:1:"))
  end

  test "lists an item's reads in the component it is passed to" do
    component = """
    defmodule LettWeb.Navigation do
      use Phoenix.Component

      def navigation(assigns) do
        ~H\"\"\"
        <.nav_item :for={item <- @navigation.items} item={item} />
        \"\"\"
      end

      def nav_item(assigns) do
        ~H\"\"\"
        <a href={@item.url}>{@item.title}</a>
        \"\"\"
      end
    end
    """

    path = "lib/lett_web/components/navigation.ex"
    igniter = migrate(%{path => component})

    assert_unchanged(igniter, [path])
    assert_has_warning(igniter, &(&1 =~ "Navigation items" and &1 =~ "#{path}:12: <a href={@item.url}>"))
  end

  @controller_path "lib/lett_web/controllers/page_controller.ex"

  @controller """
  defmodule LettWeb.PageController do
    use BrandoWeb, :controller

    alias Brando.Pages

    def index(conn, _params) do
      language = Map.get(conn.assigns, :language)

      page_opts = %{
        matches: %{uri: "index", language: language},
        status: :published,
        preload: [:alternate_entries],
        cache: {:ttl, :infinite}
      }

      with {:ok, page} <- Pages.get_page(page_opts) do
        conn
        |> assign(:page, page)
        |> render(page.template)
      end
    end

    def show(conn, %{"path" => path}) when is_list(path) do
      language = Map.get(conn.assigns, :language)

      page_opts = %{
        matches: %{path: path, language: language},
        status: :published,
        preload: [:alternate_entries],
        cache: {:ttl, :infinite}
      }

      with {:ok, page} <- Pages.get_page(page_opts) do
        render(conn, page.template, page: page)
      end
    end
  end
  """

  @header """
  <header
    data-nav
    class={render_classes(["light-header": assigns[:page] && Brando.Pages.get_var(@page, "light_header")])}>
  </header>
  """

  test "adds :vars to the page loads when a template reads the page's vars" do
    igniter = migrate(%{@navigation_path => @header, @controller_path => @controller})

    controller = source(igniter, @controller_path)
    assert count(controller, "preload: [:alternate_entries, :vars],") == 2
    refute controller =~ "preload: [:alternate_entries],"
    assert_unchanged(igniter, [@navigation_path])
    refute Enum.any?(igniter.warnings, &(&1 =~ "Page vars"))

    assert_has_notice(igniter, fn notice ->
      notice =~ "added `:vars`" and notice =~ "#{@controller_path}:16" and notice =~ "#{@controller_path}:33"
    end)

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate54.igniter()
    assert_unchanged(rerun, [@controller_path, @navigation_path])
    refute Enum.any?(rerun.warnings, &(&1 =~ "Page vars"))
  end

  test "adds a preload to a page load written with a map and none" do
    controller = """
    defmodule LettWeb.PageController do
      def index(conn, _params) do
        {:ok, page} = Brando.Pages.get_page(%{matches: %{uri: "index"}, status: :published})
        render(conn, :index, page: page)
      end
    end
    """

    igniter = migrate(%{@navigation_path => @header, @controller_path => controller})

    assert source(igniter, @controller_path) =~
             ~s|Brando.Pages.get_page(%{matches: %{uri: "index"}, status: :published, preload: [:vars]})|
  end

  test "keeps listing page var reads when a page load cannot be updated" do
    controller = """
    defmodule LettWeb.PageController do
      alias Brando.Pages

      def index(conn, _params), do: load(conn, %{matches: %{uri: "index"}, preload: [:alternate_entries]})

      defp load(conn, opts) do
        {:ok, page} = Pages.get_page(opts)
        render(conn, :index, page: page)
      end
    end
    """

    igniter = migrate(%{@navigation_path => @header, @controller_path => controller})

    assert_unchanged(igniter, [@controller_path])

    assert_has_warning(igniter, fn warning ->
      warning =~ "Page vars" and warning =~ "stays listed after you add the preload" and
        warning =~ "#{@navigation_path}:3:" and
        warning =~ "#{@controller_path}:7: `opts` is not assigned one map in the same function"
    end)
  end

  test "adds :vars to a piped page load, and keeps listing the reads for one it cannot read" do
    controller =
      @controller
      |> String.replace(
        "with {:ok, page} <- Pages.get_page(page_opts) do\n      render(",
        "with {:ok, page} <- page_opts |> Pages.get_page() do\n      render("
      )
      |> String.replace("  alias Brando.Pages\n", "  alias Brando.Pages\n  import Brando.Pages, only: [get_page: 1]\n")
      |> String.replace(
        "with {:ok, page} <- Pages.get_page(page_opts) do\n      conn",
        "with {:ok, page} <- get_page(page_opts) do\n      conn"
      )

    igniter = migrate(%{@navigation_path => @header, @controller_path => controller})

    controller = source(igniter, @controller_path)
    assert controller =~ "preload: [:alternate_entries],"
    assert count(controller, "preload: [:alternate_entries, :vars],") == 1
    assert controller =~ "page_opts |> Pages.get_page()"

    assert_has_warning(igniter, fn warning ->
      warning =~ "#{@navigation_path}:3:" and
        warning =~ "#{@controller_path}:17: a `get_page` call the task cannot read" and
        not (warning =~ "#{@controller_path}:5:")
    end)
  end

  defp count(content, pattern), do: content |> String.split(pattern) |> length() |> Kernel.-(1)

  defp migrate(files) do
    [app_name: :lett, files: files]
    |> test_project()
    |> include_test_files()
    |> Migrate54.igniter()
  end

  defp source(igniter, path), do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  defp include_test_files(igniter) do
    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, &Igniter.include_existing_file(&2, &1))
  end
end

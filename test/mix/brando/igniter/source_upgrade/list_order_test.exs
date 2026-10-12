defmodule Mix.Brando.Igniter.SourceUpgrade.ListOrderTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Brando.Igniter.SourceUpgrade.ListOrder

  # Lett before its "Order public lists explicitly" commit, trimmed to the
  # list queries: two Brando.Query contexts with `list_categories` each, five
  # Sequenced Blueprints, a controller, Blueprint datasources and a template.

  @articles """
  defmodule Lett.Articles do
    use Brando.Query
    import Ecto.Query

    alias Lett.Articles.Article
    alias Lett.Articles.Category

    query :list, Article do
      fn query -> from t in query, preload: [:cover] end
    end

    query :list, Category do
      fn query -> from(t in query) end
    end
  end
  """

  @menu """
  defmodule Lett.Menu do
    use Brando.Query
    alias Lett.Menu.{Category, Menuitem}

    query :list, Menuitem do
      fn query -> from(t in query) end
    end

    query :list, Category do
      fn query -> from(t in query) end
    end
  end
  """

  @vacancies """
  defmodule Lett.Vacancies do
    use Brando.Query
    alias Lett.Vacancies.Vacancy

    query :list, Vacancy do
      fn query -> from(t in query) end
    end
  end
  """

  @farms """
  defmodule Lett.Farms do
    use Brando.Query
    alias Lett.Farms.Farm

    query :list, Farm do
      fn query -> from(t in query) end
    end
  end
  """

  @article """
  defmodule Lett.Articles.Article do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Articles",
      schema: "Article",
      singular: "article",
      plural: "articles"

    alias Lett.Articles

    trait Brando.Trait.Sequenced
    trait Brando.Trait.Timestamped

    def last_3_featured_articles(lang) do
      Lett.Articles.list_articles(%{
        status: :published,
        order: {:asc, :sequence},
        limit: 3,
        preload: [:category, :cover],
        filter: %{featured: true, language: lang}
      })
    end

    def get_categories(_, _) do
      {:ok, categories} = Articles.list_categories(%{order: [{:asc, :language}, {:asc, :name}]})
      categories
    end
  end
  """

  @category """
  defmodule Lett.Articles.Category do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Articles",
      schema: "Category",
      singular: "category",
      plural: "categories"

    trait Brando.Trait.Sequenced
    trait Brando.Trait.Timestamped
  end
  """

  @menu_category """
  defmodule Lett.Menu.Category do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Menu",
      schema: "Category",
      singular: "category",
      plural: "categories"

    trait Brando.Trait.Sequenced
    trait Brando.Trait.Timestamped
  end
  """

  @menuitem """
  defmodule Lett.Menu.Menuitem do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Menu",
      schema: "Menuitem",
      singular: "menuitem",
      plural: "menuitems"

    alias Lett.Menu

    trait Brando.Trait.Sequenced
    trait Brando.Trait.Timestamped

    datasources do
      datasource :all do
        type :list

        list fn _, lang, _ ->
          entries_opts = %{
            filter: %{language: lang},
            order: [{:asc, :sequence}],
            preload: [:cover],
            status: :published
          }

          {:ok, items} = Menu.list_menuitems(entries_opts)
          {:ok, items}
        end
      end
    end
  end
  """

  @vacancy """
  defmodule Lett.Vacancies.Vacancy do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Vacancies",
      schema: "Vacancy",
      singular: "vacancy",
      plural: "vacancies"

    alias Lett.Vacancies

    trait Brando.Trait.Sequenced
    trait Brando.Trait.Timestamped

    datasources do
      datasource :all do
        type :list

        list fn _, lang, _ ->
          Vacancies.list_vacancies(%{
            filter: %{language: lang},
            status: :published,
            order: "asc sequence"
          })
        end
      end
    end
  end
  """

  @farm """
  defmodule Lett.Farms.Farm do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Farms",
      schema: "Farm",
      singular: "farm",
      plural: "farms"

    trait Brando.Trait.Status
    trait Brando.Trait.Timestamped
  end
  """

  @controller """
  defmodule LettWeb.ArticleController do
    use BrandoWeb, :controller
    alias Lett.Articles

    def list(conn, _params) do
      language = Map.get(conn.assigns, :language)

      list_opts = %{
        filter: %{language: language},
        order: "asc sequence",
        preload: [:category, :cover],
        status: :published
      }

      cat_opts = %{filter: %{language: language}}

      with {:ok, articles} <- Articles.list_articles(list_opts),
           {:ok, categories} <- Articles.list_categories(cat_opts) do
        render(conn, :list, articles: articles, categories: categories)
      end
    end

    def detail(conn, %{"category" => category_slug}) do
      language = Map.get(conn.assigns, :language)

      latest_articles_params = %{
        order: {:asc, :sequence},
        filter: %{category: category_slug, language: language},
        status: :published,
        preload: [:category, :cover],
        limit: 3
      }

      {:ok, latest_articles} = Articles.list_articles(latest_articles_params)
      render(conn, :detail, latest_articles: latest_articles)
    end
  end
  """

  @template """
  <main id="content" data-loader={"/api/menu/\#{@language}"}>
    <%
      {:ok, categories} = Lett.Menu.list_categories(%{
        filter: %{language: @language},
        status: :published,
        cache: {:ttl, :infinite}
      })

      {:ok, entries} = Lett.Menu.list_menuitems(%{
        filter: %{language: @language},
        order: "desc seasonal, asc sequence",
        status: :published
      })
    %>
  </main>
  """

  @paths %{
    articles: "lib/lett/articles.ex",
    menu: "lib/lett/menu.ex",
    vacancies: "lib/lett/vacancies.ex",
    farms: "lib/lett/farms.ex",
    article: "lib/lett/articles/article.ex",
    category: "lib/lett/articles/category.ex",
    menu_category: "lib/lett/menu/category.ex",
    menuitem: "lib/lett/menu/menuitem.ex",
    vacancy: "lib/lett/vacancies/vacancy.ex",
    farm: "lib/lett/farms/farm.ex",
    controller: "lib/lett_web/controllers/article_controller.ex",
    template: "lib/lett_web/controllers/page_html/menu.html.heex"
  }

  defp lett(overrides \\ %{}, step \\ &ListOrder.order_list_queries/1) do
    files = %{
      articles: @articles,
      menu: @menu,
      vacancies: @vacancies,
      farms: @farms,
      article: @article,
      category: @category,
      menu_category: @menu_category,
      menuitem: @menuitem,
      vacancy: @vacancy,
      farm: @farm,
      controller: @controller,
      template: @template
    }

    files = for {key, contents} <- Map.merge(files, overrides), into: %{}, do: {@paths[key], contents}
    igniter = test_project(app_name: :lett, files: files)

    igniter.assigns.test_files
    |> Map.keys()
    |> Enum.reduce(igniter, &Igniter.include_existing_file(&2, &1))
    |> step.()
  end

  defp source(igniter, key), do: igniter.rewrite |> Rewrite.source!(@paths[key]) |> Rewrite.Source.get(:content)

  defp sequence_only(contents, old, suffix \\ "") do
    String.replace(contents, old, ~s(order: "asc sequence, desc inserted_at") <> suffix)
  end

  test "breaks ties in queries that order only by sequence, as Lett did by hand" do
    igniter = lett()

    assert source(igniter, :article) == sequence_only(@article, "order: {:asc, :sequence}")
    assert source(igniter, :menuitem) == sequence_only(@menuitem, "order: [{:asc, :sequence}]")
    assert source(igniter, :vacancy) == sequence_only(@vacancy, ~s(order: "asc sequence"\n), "\n")

    controller =
      @controller
      |> String.replace(~s(order: "asc sequence",), ~s(order: "asc sequence, desc inserted_at",))
      |> sequence_only("order: {:asc, :sequence}")

    assert source(igniter, :controller) == controller

    assert [notice] = Enum.filter(igniter.notices, &(&1 =~ "ordered only by `sequence`"))
    assert notice =~ "lib/lett/articles/article.ex:15: Lett.Articles.list_articles(%{"
    assert notice =~ "lib/lett/menu/menuitem.ex:19: entries_opts = %{, passed to Menu.list_menuitems"
    assert notice =~ "lib/lett/vacancies/vacancy.ex:19: Vacancies.list_vacancies(%{"
    assert notice =~ "lib/lett_web/controllers/article_controller.ex:8: list_opts = %{, passed to Articles.list_articles"

    assert notice =~
             "lib/lett_web/controllers/article_controller.ex:26: latest_articles_params = %{, passed to Articles.list_articles"
  end

  test "warns about list queries without an order, with file and line" do
    igniter = lett()
    assert_unchanged(igniter, @paths.template)

    assert [warning] = Enum.filter(igniter.warnings, &(&1 =~ "leave the order of their rows"))

    assert warning =~
             "lib/lett_web/controllers/article_controller.ex:15: cat_opts = %{filter: %{language: language}}, passed to Articles.list_categories (Sequenced: order: \"asc sequence, desc inserted_at\")"

    assert warning =~
             "lib/lett_web/controllers/page_html/menu.html.heex:3: {:ok, categories} = Lett.Menu.list_categories(%{ (Sequenced: order: \"asc sequence, desc inserted_at\")"

    assert warning =~ "visible change"

    # Explicit orders, and `get_categories`' admin-side order, are left alone.
    refute warning =~ "list_menuitems"
    refute warning =~ "article.ex"
  end

  test "an order map passed as it is, or no options at all, are found for any Blueprint" do
    farms = """
    defmodule LettWeb.FarmController do
      alias Lett.Farms

      def index(conn, _params) do
        {:ok, all} = Farms.list_farms()
        {:ok, sorted} = %{order: "asc name"} |> Farms.list_farms()
        {:ok, ordered} = Farms.list_farms(%{order: "asc sequence"})
        render(conn, :index, farms: all ++ sorted ++ ordered)
      end
    end
    """

    igniter = lett(%{controller: farms})
    [warning] = Enum.filter(igniter.warnings, &(&1 =~ "leave the order of their rows"))
    assert warning =~ "article_controller.ex:5: {:ok, all} = Farms.list_farms()\n"
    refute warning =~ "article_controller.ex:6"

    # Farm is not Sequenced: ordering by `sequence` alone is warned, not rewritten.
    assert warning =~ "article_controller.ex:7: {:ok, ordered} = Farms.list_farms(%{order: \"asc sequence\"}) (orders by"
    assert source(igniter, :controller) == farms
  end

  test "a rebound or out-of-function variable, an update map and Brando's own contexts are not read" do
    controller = """
    defmodule LettWeb.ArticleController do
      alias Lett.Articles

      def list(conn, _params) do
        opts = %{order: "asc sequence"}
        opts = Map.put(opts, :limit, 3)
        {:ok, articles} = Articles.list_articles(opts)
        {:ok, more} = Articles.list_articles(%{opts | limit: 4})
        {:ok, pages} = Brando.Pages.list_pages(%{})
        render(conn, :list, articles: articles ++ more, pages: pages)
      end

      defp shared, do: %{status: :published}

      def other(conn, _params) do
        {:ok, articles} = Articles.list_articles(shared_opts)
        render(conn, :list, articles: articles)
      end
    end
    """

    igniter = lett(%{controller: controller})
    assert_unchanged(igniter, @paths.controller)

    for warning <- igniter.warnings, do: refute(warning =~ "article_controller.ex")
  end

  test "breaks ties on id for a Sequenced Blueprint without timestamps" do
    category = String.replace(@category, "  trait Brando.Trait.Timestamped\n", "")

    controller = """
    defmodule LettWeb.CategoryController do
      alias Lett.Articles

      def index(conn, _params) do
        {:ok, categories} = Articles.list_categories(%{order: "asc sequence"})
        {:ok, other} = Articles.list_categories(%{status: :published})
        render(conn, :index, categories: categories ++ other)
      end
    end
    """

    igniter = lett(%{category: category, controller: controller})

    assert source(igniter, :controller) ==
             String.replace(controller, ~s(%{order: "asc sequence"}), ~s(%{order: "asc sequence, asc id"}))

    assert Enum.any?(
             igniter.notices,
             &(&1 =~
                 ~s|article_controller.ex:5: {:ok, categories} = Articles.list_categories(%{order: "asc sequence"}) → "asc sequence, asc id"|)
           )

    assert Enum.any?(
             igniter.warnings,
             &(&1 =~
                 ~s|article_controller.ex:6: {:ok, other} = Articles.list_categories(%{status: :published}) (Sequenced: order: "asc sequence, asc id")|)
           )
  end

  test "reads each module of a file on its own" do
    # The Article Blueprint is not Sequenced; the item Blueprint after it is.
    article =
      String.replace(@article, "  trait Brando.Trait.Sequenced\n", "") <>
        """

        defmodule Lett.Articles.ArticleItem do
          use Brando.Blueprint,
            application: "Lett",
            domain: "Articles",
            schema: "ArticleItem",
            singular: "article_item",
            plural: "article_items"

          trait Brando.Trait.Sequenced
          trait Brando.Trait.Timestamped
        end
        """

    articles =
      String.replace(
        @articles,
        "  alias Lett.Articles.Category\n",
        "  alias Lett.Articles.Category\n  alias Lett.Articles.ArticleItem\n"
      )
      |> String.replace(
        "  query :list, Category do",
        "  query :list, ArticleItem do\n    fn query -> from(t in query) end\n  end\n\n  query :list, Category do"
      )

    controller = """
    defmodule LettWeb.ArticleController do
      alias Lett.Articles

      def index(conn, _params) do
        {:ok, articles} = Articles.list_articles(%{order: "asc sequence"})
        {:ok, items} = Articles.list_article_items(%{order: "asc sequence"})
        render(conn, :index, articles: articles, items: items)
      end
    end
    """

    igniter = lett(%{article: article, articles: articles, controller: controller})
    rewritten = source(igniter, :controller)

    assert rewritten =~ ~s|list_articles(%{order: "asc sequence"})|
    assert rewritten =~ ~s|list_article_items(%{order: "asc sequence, desc inserted_at"})|
  end

  test "an alias to another module is not taken for the context of the same name" do
    controller = """
    defmodule LettWeb.PageController do
      alias LettWeb.Menu

      def index(conn, _params), do: render(conn, :index, items: Menu.list_categories(%{order: "asc sequence"}))
    end
    """

    igniter = lett(%{controller: controller})
    assert source(igniter, :controller) == controller
    for warning <- igniter.warnings, do: refute(warning =~ "article_controller.ex")
  end

  test "an options map passed to calls that need different tiebreaks is warned, not rewritten" do
    category = String.replace(@category, "  trait Brando.Trait.Timestamped\n", "")

    controller = """
    defmodule LettWeb.ArticleController do
      alias Lett.Articles

      def index(conn, _params) do
        opts = %{order: "asc sequence"}
        {:ok, articles} = Articles.list_articles(opts)
        {:ok, categories} = Articles.list_categories(opts)
        shared = %{order: "asc sequence"}
        {:ok, featured} = Articles.list_articles(shared)
        {:ok, latest} = Articles.list_articles(shared)
        render(conn, :index, articles: articles ++ featured ++ latest, categories: categories)
      end
    end
    """

    igniter = lett(%{category: category, controller: controller})

    assert source(igniter, :controller) ==
             String.replace(
               controller,
               ~s(shared = %{order: "asc sequence"}),
               ~s(shared = %{order: "asc sequence, desc inserted_at"})
             )

    assert [warning] = Enum.filter(igniter.warnings, &(&1 =~ "leave the order of their rows"))

    assert warning =~
             ~s|article_controller.ex:5: opts = %{order: "asc sequence"}, passed to Articles.list_articles and Articles.list_categories (they need different tiebreaks: "asc sequence, desc inserted_at", "asc sequence, asc id")|
  end

  test "each module in a file resolves its own aliases" do
    menu_category = String.replace(@menu_category, "  trait Brando.Trait.Timestamped\n", "")

    controller = """
    defmodule LettWeb.ArticleHelpers do
      alias Lett.Articles

      def categories, do: Articles.list_categories(%{order: "asc sequence"})
    end

    defmodule LettWeb.MenuHelpers do
      alias Lett.Menu, as: Articles

      def categories, do: Articles.list_categories(%{order: "asc sequence"})
    end
    """

    rewritten = source(lett(%{menu_category: menu_category, controller: controller}), :controller)

    assert rewritten =~
             ~s|alias Lett.Articles\n\n  def categories, do: Articles.list_categories(%{order: "asc sequence, desc inserted_at"})|

    assert rewritten =~
             ~s|alias Lett.Menu, as: Articles\n\n  def categories, do: Articles.list_categories(%{order: "asc sequence, asc id"})|
  end

  test "only code is read: not strings, sigils, comments or template text" do
    controller = ~S'''
    defmodule LettWeb.ArticleController do
      @moduledoc """
      Lists articles: `Lett.Articles.list_articles(%{order: "asc sequence"})`.
      """
      alias Lett.Articles

      # Articles.list_articles(%{order: "asc sequence"})
      @example ~S"Articles.list_categories(%{status: :published})"

      def index(conn, _params) do
        {:ok, articles} = Articles.list_articles(%{order: "asc sequence"})
        render(conn, :index, articles: articles, example: @example)
      end
    end
    '''

    template = """
    <p>Call Lett.Articles.list_articles(%{order: "asc sequence"}) for more.</p>
    <span>{length(Lett.Articles.list_articles!(%{order: "asc sequence"}))}</span>
    """

    igniter = lett(%{controller: controller, template: template})

    assert source(igniter, :controller) ==
             String.replace(
               controller,
               ~s|{:ok, articles} = Articles.list_articles(%{order: "asc sequence"})|,
               ~s|{:ok, articles} = Articles.list_articles(%{order: "asc sequence, desc inserted_at"})|
             )

    assert source(igniter, :template) ==
             String.replace(
               template,
               ~s|list_articles!(%{order: "asc sequence"})|,
               ~s|list_articles!(%{order: "asc sequence, desc inserted_at"})|
             )

    for warning <- igniter.warnings do
      refute warning =~ "article_controller.ex"
      refute warning =~ "menu.html.heex"
    end
  end

  test "is idempotent" do
    igniter = lett()
    rewritten = for key <- [:article, :menuitem, :vacancy, :controller], into: %{}, do: {key, source(igniter, key)}
    rerun = lett(rewritten)

    assert Enum.filter(rerun.notices, &(&1 =~ "ordered only by `sequence`")) == []
    assert_unchanged(rerun)
  end

  test "mix brando.migrate55 orders them" do
    igniter = lett(%{}, &Mix.Tasks.Brando.Migrate55.igniter/1)

    assert source(igniter, :controller) =~ ~s(order: "asc sequence, desc inserted_at",\n      preload)
    assert Enum.any?(igniter.warnings, &(&1 =~ "article_controller.ex:15: cat_opts"))
  end
end

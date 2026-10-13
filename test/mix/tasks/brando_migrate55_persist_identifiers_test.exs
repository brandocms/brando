defmodule Mix.Tasks.Brando.Migrate55PersistIdentifiersTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate55

  @router_path "lib/lett_web/router.ex"

  # The Blueprint DSL and Phoenix routes without parentheses, as `import_deps`
  # gives an application.
  @formatter """
  [
    inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
    locals_without_parens: [
      live: 2, live: 3, trait: 1, identifier: 1, persist_identifier: 1, data_layer: 1, attribute: 3, absolute_url: 1, relation: 2, type: 1, list: 1, datasource: 2, input: 3
    ]
  ]
  """

  @router """
  defmodule LettWeb.Router do
    use BrandoWeb, :router

    import Brando.Router

    admin_routes do
      live "/", LettAdmin.DashboardLive

      scope "/menu", LettAdmin.Menu, as: :menu do
        live "/categories", CategoryListLive
        live "/categories/create", CategoryFormLive, :create
        live "/categories/update/:entry_id", CategoryFormLive, :update

        live "/menuitems", MenuitemListLive
        live "/menuitems/create", MenuitemFormLive, :create
        live "/menuitems/update/:entry_id", MenuitemFormLive, :update
      end

      live "/articles/categories", LettAdmin.Articles.CategoryListLive
      live "/articles/categories/create", LettAdmin.Articles.CategoryFormLive, :create
      live "/articles/categories/update/:entry_id", LettAdmin.Articles.CategoryFormLive, :update
    end
  end
  """

  @farm """
  defmodule Lett.Farms.Farm do
    @moduledoc \"\"\"
    Blueprint for Farm
    \"\"\"

    use Brando.Blueprint,
      application: "Lett",
      domain: "Farms",
      schema: "Farm",
      singular: "farm",
      plural: "farms"

    trait Brando.Trait.Creator
    trait Brando.Trait.Sequenced
    # trait Brando.Trait.Villain

    identifier "{{ entry.name }}"
    # absolute_url "{% route farm_path detail { entry.slug } %}"

    attributes do
      attribute :name, :string, required: true
    end

    datasources do
      datasource :farms do
        type :list
        list fn _, _, _ -> Lett.Farms.list_farms() end
      end
    end
  end
  """

  test "sets persist_identifier false on Blueprints no admin route or LiveView edits" do
    igniter = migrate(files())

    assert source(igniter, "lib/lett/farms/farm.ex") =~ """
             # trait Brando.Trait.Villain

             identifier "{{ entry.name }}"
             persist_identifier false
             # absolute_url "{% route farm_path detail { entry.slug } %}"
           """

    assert_unchanged(igniter, [
      "lib/lett/menu/category.ex",
      "lib/lett/menu/menuitem.ex",
      "lib/lett/articles/category.ex",
      "lib/lett/prices/price.ex",
      "lib/lett/projects/inline_row.ex",
      "lib/lett/pages/landing.ex",
      "lib/lett/stores/store.ex"
    ])

    assert_has_notice(igniter, fn notice ->
      notice =~ "set `persist_identifier false`" and notice =~ "`mix brando.identifiers.sync`" and
        notice =~ "Lett.Farms.Farm (lib/lett/farms/farm.ex): no `admin_farm_form_path`" and
        not (notice =~ "Lett.Menu")
    end)

    # Routed in the `as: :menu` scope without `router_scope: :menu`, so its
    # helper is missing; it has a LiveView, so it is listed, not changed.
    assert_has_warning(igniter, fn warning ->
      warning =~ "Decide whether these Blueprints persist identifiers" and
        warning =~ "Lett.Menu.Menuitem (lib/lett/menu/menuitem.ex): has admin LiveViews but no `admin_menuitem_form_path`" and
        warning =~ "Lett.Stores.Store (lib/lett/stores/store.ex): has no admin editor, but has an `absolute_url`" and
        not (warning =~ "Lett.Menu.Category")
    end)

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate55.igniter()
    assert_unchanged(rerun, ["lib/lett/farms/farm.ex"])
    refute Enum.any?(rerun.notices, &(&1 =~ "set `persist_identifier false`"))
  end

  test "lists Blueprints whose identifiers something could select" do
    producer = blueprint("Producers", "Producer", "producer")

    shop =
      blueprint(
        "Shops",
        "Shop",
        "shop",
        "",
        ~s|identifier "{{ entry.name }}"\n\n  datasources do\n    datasource :featured do\n      type :selection\n      list fn _, _, _ -> {:ok, []} end\n    end\n  end|
      )

    article =
      blueprint(
        "Articles",
        "Article",
        "article",
        "",
        ~s|identifier "{{ entry.title }}"\n\n  relations do\n    relation :related, :entries\n  end|
      )

    files =
      files()
      |> Map.put("lib/lett/producers/producer.ex", producer)
      |> Map.put("lib/lett/shops/shop.ex", shop)
      |> Map.put("lib/lett/articles/article.ex", article)

    igniter = migrate(files)

    # An `:entries` relation without `sources:` could select any of them.
    assert_unchanged(igniter, [
      "lib/lett/farms/farm.ex",
      "lib/lett/producers/producer.ex",
      "lib/lett/shops/shop.ex",
      "lib/lett/articles/article.ex"
    ])

    assert_has_warning(igniter, fn warning ->
      warning =~
        "Lett.Producers.Producer (lib/lett/producers/producer.ex): an `:entries` relation or input in lib/lett/articles/article.ex may select it" and
        warning =~
          "Lett.Shops.Shop (lib/lett/shops/shop.ex): its `:selection` datasource `:featured` selects its identifiers"
    end)

    # With sources that leave it out, the `:entries` input selects nothing of it.
    sourced =
      String.replace(
        article,
        "relation :related, :entries\n  end",
        "relation :related, :entries\n  end\n\n  forms do\n    form do\n      input :related, :entries, sources: [{Lett.Articles.Article, %{}}]\n    end\n  end"
      )

    igniter = migrate(Map.put(files, "lib/lett/articles/article.ex", sourced))
    assert source(igniter, "lib/lett/producers/producer.ex") =~ "persist_identifier false"
    assert source(igniter, "lib/lett/farms/farm.ex") =~ "persist_identifier false"
    assert_unchanged(igniter, ["lib/lett/shops/shop.ex", "lib/lett/articles/article.ex"])
  end

  # koi's Article after migrate54: it names its join schema in a relation,
  # and its `:entries` input selects only Articles.
  @koi_article """
  defmodule Lett.Articles.Article do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Articles",
      schema: "Article",
      singular: "article",
      plural: "articles"

    alias Lett.Articles

    identifier "[{{ entry.language }}] {{ entry.title }}"
    absolute_url "{% route article_path detail { entry.slug } %}"

    relations do
      relation :article_categories, :has_many,
        module: Articles.ArticleCategory,
        preload_order: [asc: :sequence],
        on_replace: :delete_if_exists

      relation :related_entries, :entries, constraints: [max_length: 3]
    end

    forms do
      form do
        tab t("Content") do
          fieldset do
            input :related_entries, :entries,
              sources: [
                {__MODULE__, %{preload: [:categories], order: "asc language, asc sequence"}}
              ],
              label: t("Related entries")
          end
        end
      end
    end
  end
  """

  @koi_article_category """
  defmodule Lett.Articles.ArticleCategory do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Articles",
      schema: "ArticleCategory",
      singular: "article_category",
      plural: "article_categories"

    alias Lett.Articles
    @allow_mark_as_deleted true

    trait Brando.Trait.Sequenced

    relations do
      relation :article, :belongs_to, module: Articles.Article
      relation :category, :belongs_to, module: Articles.Category
    end
  end
  """

  test "reads the `:entries` input's sources, not the modules its file names" do
    files =
      files()
      |> Map.put("lib/lett/articles/article.ex", @koi_article)
      |> Map.put("lib/lett/articles/article_category.ex", @koi_article_category)

    igniter = migrate(files)

    assert source(igniter, "lib/lett/articles/article_category.ex") =~
             ~s(plural: "article_categories"\n\n  persist_identifier false\n)

    refute Enum.any?(igniter.warnings, &(&1 =~ "Lett.Articles.ArticleCategory"))
    refute source(igniter, "lib/lett/articles/article.ex") =~ "persist_identifier"

    # A source written with the file's alias names the join schema.
    selecting =
      String.replace(
        @koi_article,
        "{__MODULE__, %{preload: [:categories], order: \"asc language, asc sequence\"}}",
        "{__MODULE__, %{}},\n            Articles.ArticleCategory"
      )

    igniter = migrate(Map.put(files, "lib/lett/articles/article.ex", selecting))
    refute source(igniter, "lib/lett/articles/article_category.ex") =~ "persist_identifier"

    assert_has_warning(igniter, fn warning ->
      warning =~
        "Lett.Articles.ArticleCategory (lib/lett/articles/article_category.ex): an `:entries` relation or input in lib/lett/articles/article.ex may select it"
    end)
  end

  test "resolves sources through a multi-alias and through `__MODULE__`" do
    producer = blueprint("Producers", "Producer", "producer")
    featured = blueprint("Articles.Article", "Featured", "featured")

    article =
      @koi_article
      |> String.replace(
        "  alias Lett.Articles\n",
        "  alias Lett.Articles\n  alias Lett.Producers.{Producer, Farm}\n  alias __MODULE__.Featured\n"
      )
      |> String.replace(
        "{__MODULE__, %{preload: [:categories], order: \"asc language, asc sequence\"}}",
        "{Producer, %{}},\n            Featured"
      )

    files =
      files()
      |> Map.put("lib/lett/articles/article.ex", article)
      |> Map.put("lib/lett/producers/producer.ex", producer)
      |> Map.put("lib/lett/articles/article/featured.ex", featured)

    igniter = migrate(files)

    for {module, path} <- [
          {"Lett.Producers.Producer", "lib/lett/producers/producer.ex"},
          {"Lett.Articles.Article.Featured", "lib/lett/articles/article/featured.ex"}
        ] do
      refute source(igniter, path) =~ "persist_identifier"

      assert_has_warning(igniter, fn warning ->
        warning =~ "#{module} (#{path}): an `:entries` relation or input in lib/lett/articles/article.ex may select it"
      end)
    end

    # An alias declared above the module, at the file's top level.
    file_level =
      "alias Lett.Producers.Producer\n\n" <>
        String.replace(article, "  alias Lett.Producers.{Producer, Farm}\n", "")

    igniter = migrate(Map.put(files, "lib/lett/articles/article.ex", file_level))
    refute source(igniter, "lib/lett/producers/producer.ex") =~ "persist_identifier"

    # A later alias of the same name does not reach back: at the top of the
    # file, and in the module's body after the input.
    later_alias = file_level <> "\nalias Lett.Archived.Producer\n"
    igniter = migrate(Map.put(files, "lib/lett/articles/article.ex", later_alias))
    refute source(igniter, "lib/lett/producers/producer.ex") =~ "persist_identifier"

    in_body =
      String.replace(article, "  alias Lett.Producers.{Producer, Farm}\n", "  alias Lett.Producers.Producer\n")
      |> String.replace(~r/\nend\n\z/, "\n\n  alias Lett.Archived.Producer\nend\n")

    igniter = migrate(Map.put(files, "lib/lett/articles/article.ex", in_body))
    refute source(igniter, "lib/lett/producers/producer.ex") =~ "persist_identifier"

    # An alias the task cannot resolve keeps the Blueprint.
    unresolved = String.replace(article, "  alias __MODULE__.Featured\n", "  alias unquote(:dynamic).Featured\n")
    igniter = migrate(Map.put(files, "lib/lett/articles/article.ex", unresolved))
    refute source(igniter, "lib/lett/articles/article/featured.ex") =~ "persist_identifier"
  end

  test "keeps the advice when it cannot read the router" do
    igniter = migrate(Map.delete(files(), @router_path))

    assert_unchanged(igniter, ["lib/lett/farms/farm.ex"])
    assert_has_warning(igniter, &(&1 =~ "could not read the router's admin routes"))
  end

  defp files do
    %{
      @router_path => @router,
      "lib/lett/farms/farm.ex" => @farm,
      "lib/lett/menu/category.ex" => blueprint("Menu", "Category", "category", ~s(,\n    router_scope: :menu)),
      "lib/lett/menu/menuitem.ex" => blueprint("Menu", "Menuitem", "menuitem"),
      "lib/lett/articles/category.ex" => blueprint("Articles", "Category", "category"),
      "lib/lett/prices/price.ex" => blueprint("Prices", "Price", "price", "", "data_layer :embedded"),
      "lib/lett/projects/inline_row.ex" => blueprint("Projects", "InlineRow", "inline_row", "", "identifier false"),
      "lib/lett/pages/landing.ex" => blueprint("Pages", "Landing", "landing", "", "persist_identifier true"),
      "lib/lett/stores/store.ex" =>
        blueprint("Stores", "Store", "store", "", ~s(absolute_url "{% route store_path show { entry.slug } %}")),
      "lib/lett_admin/live/menu/menuitem_list_live.ex" => """
      defmodule LettAdmin.Menu.MenuitemListLive do
        use BrandoAdmin.LiveView.Listing, schema: Lett.Menu.Menuitem
      end
      """
    }
  end

  defp blueprint(domain, schema, singular, options \\ "", body \\ ~s(identifier "{{ entry.name }}")) do
    """
    defmodule Lett.#{domain}.#{schema} do
      use Brando.Blueprint,
        application: "Lett",
        domain: "#{domain}",
        schema: "#{schema}",
        singular: "#{singular}",
        plural: "#{singular}s"#{options}

      #{body}
    end
    """
  end

  defp migrate(files) do
    [app_name: :lett, files: Map.put(files, ".formatter.exs", @formatter)]
    |> test_project()
    |> include_test_files()
    |> Migrate55.igniter()
  end

  defp source(igniter, path), do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  defp include_test_files(igniter) do
    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, &Igniter.include_existing_file(&2, &1))
  end
end

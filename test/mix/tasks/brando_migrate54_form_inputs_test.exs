defmodule Mix.Tasks.Brando.Migrate54FormInputsTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate54

  @formatter """
  [
    inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
    locals_without_parens: [
      trait: 1, identifier: 1, attribute: 2, attribute: 3, relation: 2, relation: 3, input: 2, input: 3, asset: 3
    ]
  ]
  """

  @article_path "lib/koi/articles/article.ex"
  @join_path "lib/koi/articles/article_category.ex"

  # As koi had them on 0.53.
  @article """
  defmodule Koi.Articles.Article do
    use Brando.Blueprint,
      application: "Koi",
      domain: "Articles",
      schema: "Article",
      singular: "article",
      plural: "articles"

    import KoiAdmin.Gettext
    alias Koi.Articles

    trait Brando.Trait.Sequenced

    identifier "[{{ entry.language }}] {{ entry.title }}"

    attributes do
      attribute :title, :text, required: true
    end

    relations do
      relation :article_categories, :has_many,
        module: Articles.ArticleCategory,
        preload_order: [asc: :sequence],
        on_replace: :delete_if_exists,
        cast: true

      relation :categories, :has_many,
        module: Articles.Category,
        through: [:article_categories, :category]

      relation :related_entries, :entries, constraints: [max_length: 3]
    end

    forms do
      form do
        tab t("Content") do
          fieldset size: :half do
            input :article_categories, :multi_select,
              options: &__MODULE__.get_categories/2,
              relation_key: :category_id,
              resetable: true,
              label: t("Categories")
          end

          fieldset size: :half, align: :end, shaded: true do
            input :related_entries, :entries,
              for: [
                {__MODULE__, %{preload: [:categories], order: "asc language, asc sequence"}}
              ],
              label: t("Related entries")
          end
        end
      end
    end

    def get_categories(_, _), do: []
  end
  """

  @join """
  defmodule Koi.Articles.ArticleCategory do
    use Brando.Blueprint,
      application: "Koi",
      domain: "Articles",
      schema: "ArticleCategory",
      singular: "article_category",
      plural: "article_categories"

    alias Koi.Articles
    @allow_mark_as_deleted true

    trait Brando.Trait.Sequenced

    relations do
      relation :article, :belongs_to, module: Articles.Article
      relation :category, :belongs_to, module: Articles.Category
    end
  end
  """

  test "adds relation: to a has_many multi select, from the join schema's belongs_to on relation_key" do
    igniter = migrate(%{@article_path => @article, @join_path => @join})
    article = source(igniter, @article_path)

    assert article =~ "relation_key: :category_id,\n            relation: :category,\n            resetable: true,"

    assert_has_notice(igniter, &(&1 =~ "#{@article_path}:38: `relation: :category` on input :article_categories"))

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate54.igniter()
    assert_unchanged(rerun, @article_path)
  end

  test "finds the belongs_to by its foreign_key, in a plain Ecto join schema" do
    join = """
    defmodule Koi.Articles.ArticleCategory do
      use Ecto.Schema

      schema "articles_categories" do
        belongs_to :article, Koi.Articles.Article
        belongs_to :kind, Koi.Articles.Category, foreign_key: :category_id
      end
    end
    """

    article = migrate(%{@article_path => @article, @join_path => join}) |> source(@article_path)
    assert article =~ "relation_key: :category_id,\n            relation: :kind,"
  end

  test "lists the multi selects whose relation it cannot tell" do
    join = String.replace(@join, "relation :category, :belongs_to", "relation :topic, :belongs_to")
    igniter = migrate(%{@article_path => @article, @join_path => join})

    refute source(igniter, @article_path) =~ "relation: :"

    assert_has_warning(igniter, fn warning ->
      warning =~ "#{@article_path}:38: input :article_categories" and warning =~ "relation_key: :category_id"
    end)
  end

  test "drops the entries sources options identifiers do not take, and says what it dropped" do
    igniter = migrate(%{@article_path => @article, @join_path => @join})
    article = source(igniter, @article_path)

    assert article =~ ~s|sources: [\n              {__MODULE__, %{order: "asc language"}}\n            ],|
    refute article =~ "preload: [:categories]"

    assert_has_notice(igniter, fn notice ->
      notice =~ "#{@article_path}:46:" and notice =~ "`preload: [:categories]`" and notice =~ "`order` by sequence"
    end)

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate54.igniter()
    assert_unchanged(rerun, @article_path)
  end

  test "drops order: when it names no identifier column, and lists options it cannot read" do
    article =
      @article
      |> String.replace(
        ~s|{__MODULE__, %{preload: [:categories], order: "asc language, asc sequence"}}|,
        ~s|{__MODULE__, %{order: "asc sequence", status: :published}}, {Koi.Projects.Project, @project_opts}|
      )

    igniter = migrate(%{@article_path => article, @join_path => @join})

    assert source(igniter, @article_path) =~
             ~r/sources: \[\s*\{__MODULE__, %\{status: :published\}\},\s*\{Koi.Projects.Project, @project_opts\}\s*\]/

    assert_has_warning(igniter, &(&1 =~ "#{@article_path}:46:" and &1 =~ "{Koi.Projects.Project, @project_opts}"))
  end

  defp migrate(files) do
    [app_name: :koi, files: Map.put(files, ".formatter.exs", @formatter)]
    |> test_project()
    |> include_test_files()
    |> Migrate54.igniter()
  end

  defp source(igniter, path), do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  defp include_test_files(igniter) do
    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, &Igniter.include_existing_file(&2, &1))
  end
end

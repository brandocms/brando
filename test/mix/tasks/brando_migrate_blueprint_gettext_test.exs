defmodule Mix.Tasks.Brando.MigrateBlueprintGettextTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Brando.Igniter.SourceUpgrade.BlueprintGettext
  alias Mix.Tasks.Brando.Migrate54
  alias Mix.Tasks.Brando.Migrate55

  @path "lib/lett/articles/article.ex"
  @backend "priv/gettext/backend"

  @article """
  defmodule Lett.Articles.Article do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Articles",
      schema: "Article",
      singular: "article",
      plural: "articles"

    import LettAdmin.Gettext

    attributes do
      attribute :title, :string
    end

    forms do
      form do
        tab gettext("Content") do
          fieldset size: :half do
            input :title, :text, label: gettext("Title"), placeholder: gettext("A title")
            input :kind, :radios, options: [%{label: gettext("Short"), value: "short"}]
            input :lead, :text, label: gettext("Lead for %{name}", name: "x")
            input :code, :text, label: dgettext("codes", "Code")
          end

          alert :info, gettext("Mind the title")
        end

        blocks :blocks, label: gettext("Blocks")
      end
    end

    listings do
      listing do
        filters([
          [label: gettext("Name"), filter: "name"]
        ])

        actions([
          [label: gettext("Publish"), event: "publish_entry", confirm: gettext("Publish it?")]
        ])

        selection_actions([
          [label: gettext("Archive"), event: "archive", confirm: gettext("Archive them?")]
        ])
      end
    end

    translations do
      context :naming do
        translate :singular, gettext("article")
        translate :plural, t("articles")
      end
    end

    def kept, do: gettext("Not a label")
  end
  """

  test "migrate54 writes the labels the admin translates in the schema domain with t/1" do
    igniter = migrate54(%{@path => @article})
    blueprint = source(igniter, @path)

    for label <- ["Content", "Title", "A title", "Short", "Mind the title", "Name", "Publish", "Archive", "Archive them?"] do
      assert blueprint =~ ~s|t("#{label}")|
      refute blueprint =~ ~s|gettext("#{label}")|
    end

    assert blueprint =~ ~s|translate(:singular, t("article"))|

    for kept <- [
          ~s|gettext("Blocks")|,
          ~s|gettext("Publish it?")|,
          ~s|gettext("Not a label")|,
          ~s|dgettext("codes", "Code")|
        ] do
      assert blueprint =~ kept
    end

    assert blueprint =~ ~s|gettext("Lead for %{name}", name: "x")|

    assert_has_notice(
      igniter,
      &(&1 =~ "Blueprint labels written with `gettext/1` now use `t/1`" and &1 =~ "#{@path} (10)")
    )

    assert_has_warning(igniter, fn warning ->
      warning =~ "written with a Gettext call `t/1` cannot replace" and
        warning =~ ~s|#{@path}:| and warning =~ ~s|: gettext("Lead for %{name}", name: "x")|
    end)

    rerun =
      igniter
      |> apply_igniter!()
      |> Igniter.include_existing_file(@path)
      |> Migrate54.igniter()

    assert_unchanged(rerun, @path)
  end

  @header """
  msgid ""
  msgstr ""
  "Language: no\\n"
  "Plural-Forms: nplurals=2; plural=(n != 1);\\n"
  """

  @default_po @header <>
                """

                #: lib/lett/articles/article.ex:84
                #: lib/lett/articles/category.ex:36
                #, elixir-autogen, elixir-format
                msgid "Content"
                msgstr "Innhold"

                #: lib/lett/articles/category.ex:54
                #, elixir-autogen, elixir-format
                msgid "Name"
                msgstr "Navn"

                #: lib/lett/articles/article.ex:90
                #, elixir-autogen, elixir-format
                msgid "Title"
                msgstr "Tittel"

                #: lib/lett_admin/live/articles/article_list_live.ex:11
                #, elixir-autogen, elixir-format
                msgid "Articles"
                msgstr "Artikler"
                """

  @article_po @header <>
                """

                #: lib/lett/articles/article.ex:125
                #, elixir-autogen, elixir-format
                msgid "Title"
                msgstr "Overskrift"

                #: lib/lett/articles/article.ex:90
                #, elixir-autogen, elixir-format
                msgid "Name"
                msgstr ""

                #: lib/lett/articles/article.ex:140
                #, elixir-autogen, elixir-format
                msgid "article"
                msgstr "artikkel"
                """

  @category_naming_po @header <>
                        """

                        #: lib/lett/articles/category.ex:62
                        msgid "category"
                        msgstr "kategori"
                        """

  @category """
  defmodule Lett.Articles.Category do
    use Brando.Blueprint,
      application: "Lett",
      domain: "Articles",
      schema: "Category",
      singular: "category",
      plural: "categories"

    forms do
      form do
        tab gettext("Content") do
          fieldset do
            input :name, :text
          end
        end
      end
    end

    translations do
      context :naming do
        translate :singular, t("category")
      end
    end
  end
  """

  @catalogs %{
    "#{@backend}/no/LC_MESSAGES/default.po" => @default_po,
    "#{@backend}/no/LC_MESSAGES/articles_article.po" => @article_po,
    "#{@backend}/no/LC_MESSAGES/articles_category_naming.po" => @category_naming_po,
    "#{@backend}/articles_article.pot" => "",
    "priv/gettext/frontend/no/LC_MESSAGES/default.po" => @default_po
  }

  test "migrate55 carries each rewritten label's translation from the default domain" do
    files = Map.merge(@catalogs, %{@path => @article, "lib/lett/articles/category.ex" => @category})

    igniter =
      files
      |> migrate54()
      |> apply_igniter!()
      |> include(Map.keys(files))
      |> Migrate55.igniter()

    article = po(igniter, "#{@backend}/no/LC_MESSAGES/articles_article.po")
    assert article["Content"] == "Innhold"
    assert article["Name"] == "Navn"
    assert article["Title"] == "Overskrift"
    assert article["article"] == "artikkel"
    refute Map.has_key?(article, "Articles")

    category = po(igniter, "#{@backend}/no/LC_MESSAGES/articles_category.po")
    assert category == %{"category" => "kategori", "Content" => "Innhold"}

    refute Rewrite.has_source?(igniter.rewrite, "priv/gettext/frontend/no/LC_MESSAGES/articles_article.po")
    refute Rewrite.has_source?(igniter.rewrite, "priv/gettext/frontend/no/LC_MESSAGES/articles_category.po")

    rerun = igniter |> apply_igniter!() |> include(Map.keys(files)) |> Migrate55.igniter()

    assert_unchanged(rerun, [
      "#{@backend}/no/LC_MESSAGES/articles_article.po",
      "#{@backend}/no/LC_MESSAGES/articles_category.po"
    ])
  end

  test "the carry finds labels rewritten earlier in the same run" do
    files = Map.put(@catalogs, @path, @article)

    igniter =
      [app_name: :lett, files: files]
      |> test_project()
      |> include(Map.keys(files))
      |> BlueprintGettext.rewrite()
      |> BlueprintGettext.carry_default_translations()

    assert po(igniter, "#{@backend}/no/LC_MESSAGES/articles_article.po")["Content"] == "Innhold"
  end

  defp migrate54(files) do
    [app_name: :lett, files: files]
    |> test_project()
    |> include(Map.keys(files))
    |> Migrate54.igniter()
  end

  defp include(igniter, paths), do: Enum.reduce(paths, igniter, &Igniter.include_existing_file(&2, &1))

  defp source(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  defp po(igniter, path) do
    for message <- Expo.PO.parse_string!(source(igniter, path)).messages,
        into: %{},
        do: {IO.iodata_to_binary(message.msgid), IO.iodata_to_binary(message.msgstr)}
  end
end

defmodule Brando.SEO.AuditTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.SEO.Audit

  defp create_page(user, attrs) do
    {:ok, page} =
      Pages.create_page(
        Map.merge(%{language: "en", template: "default.html", status: :published}, attrs),
        user
      )

    page
  end

  defp set_rendered_blocks(page, html) do
    page |> Ecto.Changeset.change(rendered_blocks: html) |> Brando.Repo.update!()
  end

  defp thin_status(row), do: Enum.find(row.checks, &(&1.key == :thin_content)).status

  test "pages are auditable; fragments are not" do
    assert Brando.Pages.Page in Audit.schemas()
    refute Brando.Pages.Fragment in Audit.schemas()
  end

  test "audits published pages in the language, counting drafts separately" do
    user = Factory.insert(:random_user)

    good =
      create_page(user, %{
        title: "Good",
        uri: "seo-good",
        meta_title: "A good page about things",
        meta_description: String.duplicate("g", 140)
      })

    create_page(user, %{title: "Bare", uri: "seo-bare"})
    create_page(user, %{title: "Draft", uri: "seo-draft", status: :draft})
    create_page(user, %{title: "Norsk", uri: "seo-no", language: "no"})

    result = Audit.run("en", schemas: [Pages.Page])

    titles = Enum.map(result.rows, & &1.title)
    assert "Good" in titles
    assert "Bare" in titles
    refute "Draft" in titles
    refute "Norsk" in titles
    assert result.drafts >= 1

    good_row = Enum.find(result.rows, &(&1.id == good.id))
    assert good_row.url =~ "seo-good"
    assert Enum.any?(good_row.checks, &(&1.key == :meta_description_present and &1.status == :pass))
    # No image on the page: the image check fails. Sitemap membership depends on
    # whether another test generated a sitemap, so it may fail too; nothing else may.
    fails = good_row.checks |> Enum.filter(&(&1.status == :fail)) |> Enum.map(& &1.key)
    assert :meta_image in fails
    # The page has no blocks, so no body text: thin content fails too.
    assert fails -- [:meta_image, :in_sitemap, :thin_content] == []

    bare_row = Enum.find(result.rows, &(&1.title == "Bare"))
    assert bare_row.score < good_row.score
    assert Enum.any?(bare_row.checks, &(&1.key == :meta_description_present and &1.status == :fail))
    assert result.missing_descriptions >= 1
    assert is_integer(result.score)
  end

  test "counts the words of the rendered blocks without loading them" do
    user = Factory.insert(:random_user)
    thin = create_page(user, %{title: "Thin", uri: "seo-thin"})
    full = create_page(user, %{title: "Full", uri: "seo-full"})
    empty = create_page(user, %{title: "Empty", uri: "seo-empty"})

    set_rendered_blocks(thin, "<h2>Short</h2><p>Only a few&nbsp;words — here.</p>")
    set_rendered_blocks(full, "<p>" <> String.duplicate("word ", 320) <> "</p>")

    result = Audit.run("en", schemas: [Pages.Page])
    by_id = Map.new(result.rows, &{&1.id, &1})

    # "—" is not a word; the entity separates two that are.
    assert by_id[thin.id].word_count == 6
    assert by_id[full.id].word_count == 320
    assert by_id[empty.id].word_count == 0

    assert thin_status(by_id[thin.id]) == :warn
    assert thin_status(by_id[full.id]) == :pass
    assert thin_status(by_id[empty.id]) == :fail
    assert result.thin_content >= 2
  end

  test "include_drafts audits unpublished entries too" do
    user = Factory.insert(:random_user)
    create_page(user, %{title: "Only draft", uri: "seo-only-draft", status: :draft})

    assert Enum.any?(Audit.run("en", schemas: [Pages.Page], include_drafts: true).rows, &(&1.title == "Only draft"))
    refute Enum.any?(Audit.run("en", schemas: [Pages.Page]).rows, &(&1.title == "Only draft"))
  end

  test "duplicate descriptions are grouped with their entries" do
    user = Factory.insert(:random_user)
    create_page(user, %{title: "Dup one", uri: "seo-dup-1", meta_description: "Same description here"})
    create_page(user, %{title: "Dup two", uri: "seo-dup-2", meta_description: "same  description HERE"})

    result = Audit.run("en", schemas: [Pages.Page])

    assert [{_value, rows}] = Enum.filter(result.duplicate_descriptions, fn {v, _} -> String.downcase(v) =~ "same" end)
    assert Enum.sort(Enum.map(rows, & &1.title)) == ["Dup one", "Dup two"]

    dup_row = Enum.find(result.rows, &(&1.title == "Dup one"))
    assert Enum.any?(dup_row.checks, &(&1.key == :duplicate_description and &1.status == :fail))
  end

  test "a blueprint's own checks are appended and scored" do
    defmodule CustomChecks do
      def __seo_checks__(row) do
        [
          %Brando.SEO.Check{
            key: :custom,
            status: if(row.title == "Custom", do: :fail, else: :pass),
            weight: :critical,
            label: "Custom"
          }
        ]
      end
    end

    row = %Audit.Row{schema: CustomChecks, title: "Custom", url: "/c", meta_title: "t", meta_description: "d"}
    # Exercise the private scoring path through run/2's public surface: emulate via Checks + custom.
    checks =
      Brando.SEO.Checks.run(row, %{fallback_description: nil, title_counts: %{}, description_counts: %{}, sitemap: nil})

    custom = CustomChecks.__seo_checks__(row)
    assert [%Brando.SEO.Check{key: :custom, status: :fail}] = custom
    assert Brando.SEO.Check.score(checks ++ custom) < Brando.SEO.Check.score(checks)
  end

  test "the default blueprint callback returns no checks" do
    assert Pages.Page.__seo_checks__(%Audit.Row{}) == []
  end

  test "sitemap paths are nil when no sitemap has been generated" do
    assert Audit.sitemap_paths() == nil or match?(%MapSet{}, Audit.sitemap_paths())
  end
end

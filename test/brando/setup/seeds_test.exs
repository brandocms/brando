defmodule Brando.Setup.SeedsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content
  alias Brando.Factory
  alias Brando.Navigation
  alias Brando.Pages
  alias Brando.Setup.Seeds

  defp count(schema), do: Brando.Repo.aggregate(schema, :count)

  describe "run/2" do
    test "a new SEO record gets the base URL and description setup was given" do
      import Ecto.Query
      user = Factory.insert(:random_user)
      Brando.Repo.delete_all(from(s in Brando.Sites.SEO, where: s.language == :en))

      {:ok, report} =
        Seeds.run(user, languages: [:en], seo: [base_url: "https://example.com", description: "A studio"])

      assert :"seo (en)" in report.created
      seo = Brando.Repo.get_by!(Brando.Sites.SEO, language: :en)
      assert {seo.base_url, seo.fallback_meta_description} == {"https://example.com", "A studio"}
    end

    test "seeds a renderable homepage, modules, menu and identity per language" do
      user = Factory.insert(:random_user)

      {:ok, report} = Seeds.run(user, languages: [:en])

      # The test database already carries identity/SEO rows, which the seeds
      # leave alone; the content they own is what must be created here.
      assert :"menu (en)" in report.created
      assert :"page (en)" in report.created

      page = Brando.Repo.get_by!(Pages.Page, uri: "index", language: :en)
      assert page.is_homepage
      assert page.status == :published
      assert page.title == "Index"

      # Repo inserts bypass the context rendering callbacks, so the seeds render
      # the entry themselves. Without that the first request renders nothing.
      for template <- ~w(hero steps cards tips terminal closing) do
        assert page.rendered_blocks =~ ~s(b-tpl="#{template}")
      end

      assert page.rendered_blocks =~ "<h1>"
      assert page.rendered_blocks =~ "mix brando.setup"

      # The toolbox table documents the framework, so it renders from the
      # module markup rather than from editable refs.
      assert page.rendered_blocks =~ "brando<span class=\"punct\">.</span>install"
      assert page.rendered_blocks =~ "task plans"

      assert Brando.Repo.get_by(Navigation.Menu, key: "main", language: :en)

      for uid <- ~w(hero steps cards tips terminal closing footer) do
        assert Brando.Repo.get_by(Content.Module, uid: "brando-default-#{uid}")
      end

      assert Brando.Repo.get_by(Pages.Fragment, parent_key: "partials", key: "footer")
      assert {:ok, _identity} = Brando.Sites.get_identity(%{matches: %{language: :en}})
      assert {:ok, _seo} = Brando.Sites.get_seo(%{matches: %{language: :en}})
    end

    test "is idempotent" do
      user = Factory.insert(:random_user)

      {:ok, _first} = Seeds.run(user, languages: [:en])

      counts = {count(Pages.Page), count(Content.Module), count(Navigation.Menu), count(Pages.Fragment)}

      {:ok, second} = Seeds.run(user, languages: [:en])

      assert second.created == []
      assert length(second.skipped) == 4
      assert :"menu (en)" in second.skipped
      assert counts == {count(Pages.Page), count(Content.Module), count(Navigation.Menu), count(Pages.Fragment)}
    end

    test "existing content of one kind does not block the rest" do
      user = Factory.insert(:random_user)
      Factory.insert(:page, uri: "index", language: :en, status: :published)

      {:ok, report} = Seeds.run(user, languages: [:en])

      assert Enum.any?(report.skipped, &(&1 == :"page (en)"))
      assert Brando.Repo.get_by(Navigation.Menu, key: "main", language: :en)
      assert count(Pages.Page) == 1
    end
  end
end

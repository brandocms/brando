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
      assert page.rendered_blocks =~ "Welcome to"
      assert page.rendered_blocks =~ "b-tpl=\"hero\""
      assert page.rendered_blocks =~ "b-tpl=\"text\""

      assert Brando.Repo.get_by(Navigation.Menu, key: "main", language: :en)
      assert Brando.Repo.get_by(Content.Module, uid: "brando-default-hero")
      assert Brando.Repo.get_by(Content.Module, uid: "brando-default-text")
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

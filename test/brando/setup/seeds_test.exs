defmodule Brando.Setup.SeedsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content
  alias Brando.Factory
  alias Brando.Navigation
  alias Brando.Pages
  alias Brando.Setup.Seeds

  import Brando.Test.Support, only: [put_test_env: 2]

  defp count(schema), do: Brando.Repo.aggregate(schema, :count)

  @public_schemas [
    Content.Module,
    Pages.Page,
    Pages.Fragment,
    Navigation.Menu,
    Brando.Sites.Identity,
    Brando.Sites.SEO
  ]

  defp shell_output(output \\ "") do
    receive do
      {:mix_shell, :info, [message]} -> shell_output(output <> message)
    after
      0 -> output
    end
  end

  defp public_counts, do: Brando.Tenant.with_public(fn -> Enum.map(@public_schemas, &count/1) end)

  # Seeds.run/2 refills the identity, SEO and navigation caches from this
  # test's sandboxed rows. The rows roll back; the global caches don't, and
  # later tests (the JSON-LD schema test) would read this test's SEO.
  setup do
    cached = Map.new(~w(identity seo navigation)a, &{&1, Brando.Cache.get(&1)})

    on_exit(fn ->
      Enum.each(cached, fn
        {key, nil} -> Brando.Cache.del(key)
        {key, value} -> Brando.Cache.put(key, value, :infinite)
      end)
    end)
  end

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

    test "seeded blocks are on their module's current version" do
      user = Factory.insert(:random_user)

      {:ok, report} = Seeds.run(user, languages: [:en])

      seeded = report.modules |> Map.values() |> MapSet.new(& &1.id)

      stale =
        for {module, count} <- Content.Blocks.count_stale_blocks_by_module(), module.id in seeded, do: {module.uid, count}

      assert stale == []
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

    test "a seeded block for a module an editor has changed is reported as outdated" do
      user = Factory.insert(:random_user)
      {:ok, %{modules: %{hero: hero}}} = Seeds.run(user, languages: [:en])

      # An editor changes the module before the second language is seeded
      hero |> Ecto.Changeset.change(version: 2) |> Brando.Repo.update!()
      {:ok, _report} = Seeds.run(user, languages: [:no])

      stale = Map.new(Content.Blocks.count_stale_blocks_by_module(), fn {module, count} -> {module.id, count} end)

      # Both pages' hero blocks are built from the seed's definition, the
      # second one too
      assert stale[hero.id] == 2
    end

    test "seeds the same records, in the same order, without tenancy" do
      user = Factory.insert(:random_user)

      {:ok, report} = Seeds.run(user, languages: [:en, :no])

      labels = Enum.reverse(report.created) ++ Enum.reverse(report.skipped)

      assert Enum.sort(labels) ==
               Enum.sort(for l <- [:en, :no], kind <- ~w(identity seo menu page), do: :"#{kind} (#{l})")

      assert Enum.filter(Enum.reverse(report.created), &(&1 in [:"menu (en)", :"page (en)", :"menu (no)", :"page (no)"])) ==
               [:"menu (en)", :"page (en)", :"menu (no)", :"page (no)"]

      assert report.modules |> Map.keys() |> Enum.sort() == ~w(cards closing footer hero steps terminal tips)a

      for language <- [:en, :no] do
        assert Brando.Repo.get_by(Pages.Page, uri: "index", language: language, is_homepage: true)
        assert Brando.Repo.get_by(Navigation.Menu, key: "main", language: language)
        assert Brando.Repo.get_by(Pages.Fragment, parent_key: "partials", key: "footer", language: language)
      end
    end

    # A site's content belongs to its environment, which `Brando.Tenant.Seeder`
    # seeds when the site is provisioned
    for mode <- [:single, :multi] do
      test "with tenancy_mode #{inspect(mode)}, setup writes nothing to public, and says why" do
        put_test_env(:tenancy_mode, unquote(mode))
        put_test_env(:site_key, "acme")
        Factory.insert(:random_user, role: :superuser)
        shell = Mix.shell()
        Mix.shell(Mix.Shell.Process)

        on_exit(fn ->
          Mix.shell(shell)
          Mix.Task.reenable("brando.gen.seeds")
        end)

        counts = public_counts()

        Mix.Task.reenable("brando.gen.seeds")
        Mix.Tasks.Brando.Setup.run(~w(--no-assets --no-db --no-account --base-url https://acme.test))

        assert public_counts() == counts
        output = shell_output()
        assert output =~ "a site gets its content when it is\nprovisioned"
        assert output =~ "--base-url is unused"
        refute output =~ "--description"
        refute_received {:mix_shell, :prompt, _}
      end

      test "with tenancy_mode #{inspect(mode)}, seeding outside an environment raises" do
        put_test_env(:tenancy_mode, unquote(mode))
        put_test_env(:site_key, "acme")
        user = Factory.insert(:random_user)
        counts = public_counts()

        assert_raise ArgumentError, ~r/site's environment/, fn -> Seeds.run(user, languages: [:en]) end
        assert public_counts() == counts
      end
    end

    test "a failing run leaves nothing written, and nothing it rendered cached" do
      user = Factory.insert(:random_user)
      modules = count(Content.Module)
      Brando.Cache.del(:navigation)

      # English is seeded and rendered before the second language fails
      assert_raise Ecto.Query.CastError, fn -> Seeds.run(user, languages: [:en, :unsupported]) end

      assert count(Content.Module) == modules
      refute Brando.Repo.get_by(Navigation.Menu, key: "main", language: :en)
      refute Brando.Repo.get_by(Pages.Page, uri: "index", language: :en)

      # The render read the rolled-back menu into the navigation cache
      refute Brando.Cache.get(:navigation)

      {:ok, _report} = Seeds.run(user, languages: [:en])
      page = Brando.Repo.get_by!(Pages.Page, uri: "index", language: :en)
      assert page.rendered_blocks =~ ~s(b-tpl="hero")
      assert Brando.Cache.Navigation.get("main", "en")
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

defmodule Mix.Tasks.Brando.Entries.ResaveTest do
  use Brando.ConnCase

  alias Mix.Tasks.Brando.Entries.Resave

  # Swaps the global `Mix.shell()`; Brando.ConnCase runs synchronously.
  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)

    Mix.Task.reenable("brando.entries.resave")
    Mix.Task.reenable("run")
    :ok
  end

  test "with nobody to answer the prompt, it does nothing and fails" do
    send(self(), {:mix_shell_input, :prompt, :eof})

    assert_raise Mix.Error, ~r/stdin is closed, so nothing was done. Pass --yes/, fn -> Resave.run([]) end
    refute_received {:mix_shell, :info, ["\n==> Done.\n"]}
  end

  test "answering no says nothing was done" do
    send(self(), {:mix_shell_input, :prompt, "n"})

    Resave.run([])

    assert_received {:mix_shell, :info, ["Nothing was done."]}
  end

  test "--yes is accepted" do
    Resave.run(["--yes", "Brando.Pages.Fragment"])

    assert_received {:mix_shell, :info, ["\n==> Done.\n"]}
  end

  test "says that running servers keep their cached pages" do
    Resave.run(["--yes", "Brando.Pages.Fragment"])

    assert_received {:mix_shell, :info,
                     ["Servers that were already running keep serving what they cached before." <> _ = note]}

    assert note =~ "Configuration → Utilities → Clear caches"
  end

  test "ends with one line per image config target that no longer resolves" do
    for n <- 1..10,
        do:
          Brando.Factory.insert(:image, path: "images/gallery/#{n}.jpg", config_target: "image:Brando.Pages.Page:gallery")

    Resave.run(["--yes", "Brando.Pages.Fragment"])

    assert_received {:mix_shell, :info,
                     [
                       "    * 10 images point at a field Brando.Pages.Page no longer has (image:Brando.Pages.Page:gallery); they use the default image config."
                     ]}
  end

  test "prints no colour codes when stdout is not a terminal" do
    ansi = Application.get_env(:elixir, :ansi_enabled)
    Application.put_env(:elixir, :ansi_enabled, false)
    on_exit(fn -> Application.put_env(:elixir, :ansi_enabled, ansi) end)

    user = Brando.Factory.insert(:random_user)
    Brando.Factory.insert(:fragment, creator: user, key: "plain", title: "Plain")

    output = ExUnit.CaptureIO.capture_io(fn -> Resave.run(["--yes", "Brando.Pages.Fragment"]) end)

    assert output =~ "done!"
    refute output =~ "\e["
  end

  test "renders each entry from what it holds when its turn comes, not when the task began" do
    user = Brando.Factory.insert(:random_user, role: :superuser)

    {:ok, module} =
      Brando.Content.create_module(
        Brando.Factory.params_for(:module, %{code: ~s(<div class="paragraph">Title: {{ entry.title }}</div>)}),
        :system
      )

    [_first, second] = for key <- ~w(first second), do: fragment(user, module, key)

    # An editor saves the second entry while the task renders the first
    id = make_ref()
    :ok = :telemetry.attach(id, [:brando, :villain, :parse_and_render], &__MODULE__.save_once/4, second.id)
    on_exit(fn -> :telemetry.detach(id) end)

    ExUnit.CaptureIO.capture_io(fn -> Resave.run(["--yes", "Brando.Pages.Fragment"]) end)

    assert Brando.Repo.get!(Brando.Pages.Fragment, second.id).rendered_blocks =~ "Title: Saved meanwhile"
  end

  @doc false
  def save_once(_event, _measurements, _metadata, id) do
    unless Process.put(:resave_test_saved, true) do
      Brando.Repo.update_all(Ecto.Query.from(f in Brando.Pages.Fragment, where: f.id == ^id),
        set: [title: "Saved meanwhile"]
      )
    end
  end

  defp fragment(user, module, key) do
    {:ok, fragment} =
      %Brando.Pages.Fragment{}
      |> Ecto.Changeset.change(
        Brando.Factory.params_for(:fragment, %{
          parent_key: "resave",
          key: key,
          title: key,
          entry_blocks: [
            %{block: %{type: :module, source: "Elixir.Brando.Pages.Fragment.Blocks", module_id: module.id, refs: []}}
          ]
        })
      )
      |> Brando.Pages.create_fragment(user)

    fragment
  end

  test "an unknown option or a second Blueprint stops the task" do
    assert_raise Mix.Error, ~r/unknown or invalid option --all. It takes: --yes, --force/, fn -> Resave.run(["--all"]) end

    assert_raise Mix.Error, ~r/unexpected argument Brando.Pages.Fragment Brando.Pages.Page/, fn ->
      Resave.run(["Brando.Pages.Fragment", "Brando.Pages.Page"])
    end
  end

  test "--site and --environment need tenancy" do
    assert_raise Mix.Error, ~r/--site and --environment need tenancy/, fn ->
      Resave.run(["--yes", "--site", "acme", "Brando.Pages.Page"])
    end
  end

  describe "with tenancy" do
    @prefixes ~w(tenant_acme_production tenant_acme_staging tenant_beta_production tenant_beta_staging)

    defmodule Migrator do
      @moduledoc false
      @behaviour Brando.Environments.Migrator

      @impl true
      def migrate(_site, _environment), do: {:ok, []}
    end

    setup do
      creator = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil)
      # public's own tables, which a site with tenancy leaves behind
      public = stale_page!(nil, creator)

      root = Path.join(System.tmp_dir!(), "brando-resave-#{System.unique_integer([:positive])}")

      put_test_env(:media_path, Path.join(root, "media"))
      put_test_env(:sites_path, Path.join(root, "sites"))
      put_test_env(:tenant_migrator, Migrator)
      put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)
      put_test_env(:tenancy_mode, :multi)
      Brando.Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()

      on_exit(fn ->
        File.rm_rf(root)
        Brando.Tenant.put_prefix(nil)
        Brando.Tenant.Cache.clear()
        Brando.TenantCaches.clear(@prefixes)
      end)

      for key <- ~w(acme beta) do
        {:ok, _site} =
          Brando.Tenant.Setup.create_site(
            %{name: String.capitalize(key), key: key, languages: ["en"], default_language: "en", status: :active},
            creator,
            environments: [
              %{name: "Production", key: "production", live: true},
              %{name: "Staging", key: "staging", live: false}
            ]
          )
      end

      pages = for prefix <- @prefixes, into: %{}, do: {prefix, stale_page!(prefix, creator)}

      %{pages: pages, public: public}
    end

    test "re-saves the entries of every environment of every site, each under its own prefix", context do
      output = ExUnit.CaptureIO.capture_io(fn -> Resave.run(["--yes", "Brando.Pages.Page"]) end)

      assert stale(context) == ["public"]
      assert output =~ "done!"
      refute output =~ "failed!"

      for {site, environment} <- [
            {"Acme (acme)", "Production"},
            {"Acme (acme)", "Staging"},
            {"Beta (beta)", "Production"},
            {"Beta (beta)", "Staging"}
          ] do
        assert_received {:mix_shell, :info, ["\n==> " <> ^site <> " → " <> rest]}
        assert rest =~ environment
      end

      assert_received {:mix_shell, :info, ["\nResaved " <> count]}
      assert count =~ ~r/^\d+ entries in 4 environments\.$/
      assert_received {:mix_shell, :info, ["\n==> Done.\n"]}
    end

    test "with Villain's query cache on, each environment's pages render its fragments as stored, not as cached" do
      Application.put_env(:brando, :villain_query_cache, true)
      Cachex.clear(:query)

      on_exit(fn ->
        Application.delete_env(:brando, :villain_query_cache)
        Cachex.clear(:query)
      end)

      user = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil)
      prefixes = ~w(tenant_acme_production tenant_beta_production)

      pages =
        for prefix <- prefixes, into: %{} do
          Brando.Tenant.with_prefix(prefix, fn ->
            fragment = cached_fragment!(user)
            page = page_embedding!(user, fragment)

            # What this node cached before the fragment was rewritten where
            # it did not hear of it
            {:ok, [_ | _]} = Brando.Pages.FragmentQuery.list_for_rendering(%{cache: {:ttl, :infinite}})

            {1, _} =
              Brando.Repo.update_all(Ecto.Query.from(f in Brando.Pages.Fragment, where: f.id == ^fragment.id),
                set: [rendered_blocks: "<p>Stored in #{prefix}</p>"]
              )

            {prefix, page.id}
          end)
        end

      ExUnit.CaptureIO.capture_io(fn -> Resave.run(["--yes", "--environment", "production", "Brando.Pages.Page"]) end)

      for {prefix, page_id} <- pages do
        Brando.Tenant.with_prefix(prefix, fn ->
          assert Brando.Repo.get!(Brando.Pages.Page, page_id).rendered_blocks == "<p>Stored in #{prefix}</p>"
        end)
      end
    end

    test "--site and --environment narrow it", context do
      run = fn args -> ExUnit.CaptureIO.capture_io(fn -> Resave.run(["--yes" | args] ++ ["Brando.Pages.Page"]) end) end

      run.(["--site", "beta", "--environment", "staging"])
      assert stale(context) == ~w(public tenant_acme_production tenant_acme_staging tenant_beta_production)

      run.(["--environment", "production"])
      assert stale(context) == ~w(public tenant_acme_staging)

      run.(["--site", "acme"])
      assert stale(context) == ["public"]
    end

    test "an unknown site or environment stops it before anything is done", context do
      assert_raise Mix.Error, ~r/no site has the key "gamma"/, fn -> Resave.run(["--yes", "--site", "gamma"]) end

      assert_raise Mix.Error, ~r/no environment matches --site acme and --environment lab/, fn ->
        Resave.run(["--yes", "--site", "acme", "--environment", "lab"])
      end

      assert length(stale(context)) == 5
    end

    test "in :single mode, re-saves the environments' entries, not public's", context do
      put_test_env(:tenancy_mode, :single)
      put_test_env(:site_key, "acme")

      ExUnit.CaptureIO.capture_io(fn -> Resave.run(["--yes", "--site", "acme", "Brando.Pages.Page"]) end)

      assert stale(context) == ~w(public tenant_beta_production tenant_beta_staging)
    end
  end

  # A published page whose stored render is out of date, in `prefix`
  defp stale_page!(prefix, user) do
    Brando.Tenant.with_prefix(prefix, fn ->
      {:ok, page} =
        Brando.Pages.create_page(
          %{
            title: "About",
            uri: "about-#{System.unique_integer([:positive])}",
            language: "en",
            template: "default.html",
            status: :published
          },
          user
        )

      {1, _} =
        Brando.Repo.update_all(Ecto.Query.from(p in Brando.Pages.Page, where: p.id == ^page.id),
          set: [rendered_blocks: "stale"]
        )

      page.id
    end)
  end

  defp cached_fragment!(user) do
    params = Brando.Factory.params_for(:fragment, %{parent_key: "cached", key: "embedded"})
    {:ok, fragment} = Brando.Pages.create_fragment(Ecto.Changeset.change(%Brando.Pages.Fragment{}, params), user)
    fragment
  end

  defp page_embedding!(user, fragment) do
    {:ok, page} =
      %Brando.Pages.Page{}
      |> Brando.Pages.Page.changeset(Brando.Factory.params_for(:page, %{creator_id: user.id}), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [
        %{block: %{type: :fragment, source: "Elixir.Brando.Pages.Page.Blocks", fragment_id: fragment.id, sequence: 0}}
      ])
      |> Map.put(:action, :insert)
      |> Brando.Pages.create_page(user)

    page
  end

  # Where the stale pages still are
  defp stale(%{pages: pages, public: public}) do
    [{"public", public} | Enum.sort(pages)]
    |> Enum.filter(fn
      {"public", id} ->
        Brando.Repo.get!(Brando.Pages.Page, id, prefix: "public").rendered_blocks == "stale"

      {prefix, id} ->
        Brando.Tenant.with_prefix(prefix, fn -> Brando.Repo.get!(Brando.Pages.Page, id).rendered_blocks == "stale" end)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  describe "Mix.Brando.confirm?/2" do
    test "--yes and --force answer without asking" do
      assert Mix.Brando.confirm?("Proceed?", yes: true)
      assert Mix.Brando.confirm?("Proceed?", force: true)
      refute_received {:mix_shell, :prompt, _}
    end

    test "an empty answer or y is yes, anything else no" do
      for {answer, expected} <- [{"", true}, {"y", true}, {"Yes\n", true}, {"n", false}, {"nope", false}] do
        send(self(), {:mix_shell_input, :prompt, answer})
        assert Mix.Brando.confirm?("Proceed?") == expected
      end
    end
  end
end

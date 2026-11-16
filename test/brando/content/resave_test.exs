defmodule Brando.Content.ResaveTest do
  use Brando.ConnCase

  import ExUnit.CaptureIO

  alias Brando.Content.Resave

  setup do
    user = Brando.Factory.insert(:random_user)
    fragment = Brando.Factory.insert(:fragment, creator: user, key: "resaved", title: "Resaved")

    {1, _} =
      Brando.Repo.update_all(Ecto.Query.from(f in Brando.Pages.Fragment, where: f.id == ^fragment.id),
        set: [rendered_blocks: "stale"]
      )

    %{fragment: fragment}
  end

  # As `bin/my_app rpc` runs it: the application is running, and the report
  # goes to standard output
  test "on a running node it re-saves, reports, and reloads the node's caches", %{fragment: fragment} do
    Cachex.put(:query, {:resave_test, :cached}, :cached)

    output = capture_io(fn -> assert {:ok, 1} = Resave.run(blueprint: "Brando.Pages.Fragment") end)

    assert Brando.Repo.get!(Brando.Pages.Fragment, fragment.id).rendered_blocks != "stale"
    assert output =~ "==> Resaving fragment entries"
    assert output =~ "done!"
    assert output =~ ~r/Resaved \d+ entr(y|ies)\./
    assert output =~ "Emptied this node's query cache and reloaded its site caches"
    assert {:ok, nil} = Cachex.get(:query, {:resave_test, :cached})
  end

  test "reload_caches: false leaves the caches and says how to empty them" do
    Cachex.put(:query, {:resave_test, :kept}, :cached)

    output = capture_io(fn -> Resave.run(blueprint: Brando.Pages.Fragment, reload_caches: false) end)

    assert output =~ "Servers that were already running keep serving what they cached before."
    assert {:ok, :cached} = Cachex.get(:query, {:resave_test, :kept})
  end

  test "lists every Blueprint and asks before re-saving them all" do
    parent = self()

    output =
      capture_io(fn ->
        decline = fn plan ->
          send(parent, {:plan, plan})
          false
        end

        assert {:ok, :declined} = Resave.run(confirm: decline, reload_caches: false)
      end)

    assert output =~ "Blueprint schemas that will be resaved"
    assert output =~ "Nothing was done."
    assert_received {:plan, %{blueprints: [Brando.Pages.Fragment | _] = blueprints, environments: [nil]}}
    assert Brando.Pages.Page in blueprints
  end

  describe "with Villain's production query caching on" do
    setup do
      Application.put_env(:brando, :villain_query_cache, true)
      Cachex.clear(:query)

      on_exit(fn ->
        Application.delete_env(:brando, :villain_query_cache)
        Cachex.clear(:query)
      end)

      %{user: Brando.Factory.insert(:random_user)}
    end

    defp module_fragment(user, key, html) do
      {:ok, module} = Brando.Content.create_module(Brando.Factory.params_for(:module, %{code: html}), :system)
      fragment_with(user, key, %{type: :module, module_id: module.id, refs: []})
    end

    defp fragment_with(user, key, block) do
      block = Map.put(block, :source, "Elixir.Brando.Pages.Fragment.Blocks")
      params = Brando.Factory.params_for(:fragment, %{parent_key: "cached", key: key, entry_blocks: [%{block: block}]})
      {:ok, fragment} = Brando.Pages.create_fragment(Ecto.Changeset.change(%Brando.Pages.Fragment{}, params), user)
      fragment
    end

    defp make_stale(schema, ids) do
      Brando.Repo.update_all(Ecto.Query.from(e in schema, where: e.id in ^ids), set: [rendered_blocks: "OLD HTML"])
    end

    defp rendered(schema, id), do: Brando.Repo.get!(schema, id).rendered_blocks

    setup %{user: user, fragment: fragment} do
      # It embeds a fragment re-saved after it, by id
      outer = fragment_with(user, "outer", %{type: :fragment, fragment_id: fragment.id})
      inner = module_fragment(user, "inner", "<p>Inner, re-rendered</p>")

      {1, _} =
        Brando.Repo.update_all(Ecto.Query.from(b in Brando.Content.Block, where: b.fragment_id == ^fragment.id),
          set: [fragment_id: inner.id]
        )

      page_cs =
        %Brando.Pages.Page{}
        |> Brando.Pages.Page.changeset(Brando.Factory.params_for(:page, %{creator_id: user.id}), user)
        |> Ecto.Changeset.put_assoc(:entry_blocks, [
          %{block: %{type: :fragment, source: "Elixir.Brando.Pages.Page.Blocks", fragment_id: outer.id, sequence: 0}}
        ])
        |> Map.put(:action, :insert)

      {:ok, page} = Brando.Pages.create_page(page_cs, user)

      make_stale(Brando.Pages.Fragment, [outer.id, inner.id])
      make_stale(Brando.Pages.Page, [page.id])
      # What a server that read them before they were rewritten holds
      {:ok, _} = Brando.Pages.FragmentQuery.list_for_rendering(%{cache: {:ttl, :infinite}})

      %{outer: outer, inner: inner, page: page}
    end

    test "a fragment renders the fragments it embeds as just re-saved, whatever their order",
         %{outer: outer, inner: inner} do
      capture_io(fn -> assert {:ok, _} = Resave.run(blueprint: Brando.Pages.Fragment, reload_caches: false) end)

      assert rendered(Brando.Pages.Fragment, inner.id) == "<p>Inner, re-rendered</p>"
      assert rendered(Brando.Pages.Fragment, outer.id) == "<p>Inner, re-rendered</p>"
    end

    test "an entry renders the fragments as stored, not as this node cached them before", %{outer: outer, page: page} do
      # Rewritten where this node did not hear of it
      Brando.Repo.update_all(Ecto.Query.from(f in Brando.Pages.Fragment, where: f.id == ^outer.id),
        set: [rendered_blocks: "<p>Stored</p>"]
      )

      capture_io(fn -> assert {:ok, 1} = Resave.run(blueprint: Brando.Pages.Page, reload_caches: false) end)

      assert rendered(Brando.Pages.Page, page.id) == "<p>Stored</p>"
    end
  end

  test "an option that names nothing is an error, before anything is done" do
    capture_io(fn ->
      assert {:error, "--site and --environment need tenancy, which is off"} = Resave.run(site: "acme")
      assert {:error, "Brando.Nothing is not a Blueprint"} = Resave.run(blueprint: "Brando.Nothing")
    end)
  end

  test "an option it does not take is an error, printed, before anything is done", %{fragment: fragment} do
    output =
      capture_io(fn ->
        assert {:error, "unknown option enviroment:" <> _} = Resave.run(enviroment: "staging")
        assert {:error, "site: must be a key, as a string, got: :acme"} = Resave.run(site: :acme)
        assert {:error, "the options must be a keyword list" <> _} = Resave.run(%{site: "acme"})
      end)

    assert output =~ "Nothing was done: unknown option enviroment:. It takes: blueprint:, site:, environment:"
    assert Brando.Repo.get!(Brando.Pages.Fragment, fragment.id).rendered_blocks == "stale"

    # The Mix task reports it itself
    assert capture_io(fn -> Resave.run(enviroment: "staging", info: fn _ -> :ok end) end) == ""
  end

  # An `rpc` session that closed: its group leader is gone
  test "a report the caller's output cannot take does not stop the run", %{fragment: fragment} do
    Cachex.put(:query, {:resave_test, :closed}, :cached)
    closed = spawn(fn -> :ok end)
    ref = Process.monitor(closed)
    assert_receive {:DOWN, ^ref, :process, ^closed, _}

    task =
      Task.async(fn ->
        Process.group_leader(self(), closed)
        Resave.run(blueprint: Brando.Pages.Fragment)
      end)

    assert {:ok, 1} = Task.await(task)
    assert Brando.Repo.get!(Brando.Pages.Fragment, fragment.id).rendered_blocks != "stale"
    assert {:ok, nil} = Cachex.get(:query, {:resave_test, :closed})
  end

  test "the caches are reloaded when a re-save fails" do
    Cachex.put(:query, {:resave_test, :failed}, :cached)

    capture_io(fn ->
      assert_raise UndefinedFunctionError, fn ->
        Resave.run(blueprint: Brando.Blueprint.Identifier.HEExTest.HEExAbsoluteURLSchema)
      end
    end)

    assert {:ok, nil} = Cachex.get(:query, {:resave_test, :failed})
  end

  describe "started by eval" do
    setup do
      saved =
        for {app, key} <- [
              {:brando, Brando.Tenant.ServedHosts},
              {:brando, :markdown_sources},
              {:brando, Oban},
              {:resave_eval_app, Oban}
            ],
            do: {app, key, Application.fetch_env(app, key)}

      level = Logger.level()

      on_exit(fn ->
        for {app, key, value} <- saved do
          case value do
            {:ok, value} -> Application.put_env(app, key, value)
            :error -> Application.delete_env(app, key)
          end
        end

        Logger.configure(level: level)
        Application.stop(:resave_eval_app)
        Application.unload(:resave_eval_app)
      end)

      spec = [description: ~c"eval", vsn: ~c"1.0.0", modules: [], registered: [], applications: [:kernel, :stdlib]]
      :ok = :application.load({:application, :resave_eval_app, spec})
      Application.put_env(:resave_eval_app, Oban, repo: Brando.Repo.repo(), queues: [default: 1])
      Application.put_env(:brando, Brando.Tenant.ServedHosts, file: "/srv/my_app/shared/served_hosts")
      :ok
    end

    test "it starts the application without what must not run beside the serving VM" do
      output =
        capture_io(fn -> assert {:ok, 1} = Resave.run(otp_app: :resave_eval_app, blueprint: "Brando.Pages.Fragment") end)

      assert List.keymember?(Application.started_applications(), :resave_eval_app, 0)
      assert Application.get_env(:brando, Oban)[:testing] == :manual
      assert Application.get_env(:resave_eval_app, Oban)[:testing] == :manual
      assert Application.get_env(:brando, Brando.Tenant.ServedHosts)[:file] == nil
      assert Keyword.fetch!(Application.get_env(:brando, :markdown_sources), :github_meta_url) == nil
      assert output =~ "bin/"
      assert output =~ ~s{rpc "Brando.Cache.reload_all()"}
    end

    test "an application it cannot load is an error, before any application env is changed" do
      env = for {app, key} <- [{:brando, Oban}, {:brando, Brando.Tenant.ServedHosts}], do: Application.get_env(app, key)

      capture_io(fn ->
        assert {:error, "cannot load the application :resave_no_such_app" <> _} =
                 Resave.run(otp_app: :resave_no_such_app, blueprint: "Brando.Pages.Fragment")
      end)

      assert env ==
               for(
                 {app, key} <- [{:brando, Oban}, {:brando, Brando.Tenant.ServedHosts}],
                 do: Application.get_env(app, key)
               )
    end
  end

  # `Node.alive?()` and whether the application is started: a distributed node
  # whose application is not started is an `rpc` to a release still booting
  test "it starts the application only on a node that is not distributed" do
    assert Resave.start_mode(false, true) == :running
    assert Resave.start_mode(true, true) == :running
    assert Resave.start_mode(false, false) == :eval
    assert Resave.start_mode(true, false) == :not_started
  end
end

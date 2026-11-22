defmodule Brando.MCP.FigmaOAuthConcurrencyTest do
  # Renewing a Figma OAuth access token under the settings row's lock, on
  # real connections outside the sandbox, so that the lock, the wait and the
  # commit between them are real.
  use ExUnit.Case, async: false

  import Brando.FigmaOAuthHelpers
  import Brando.Test.Support, only: [put_test_env: 2]
  import Ecto.Query, only: [from: 2]

  alias Brando.Figma
  alias Brando.Figma.OAuth
  alias Brando.MCP
  alias Brando.MCP.Setting
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    tenant = MCP.tenant(nil, nil)

    {user, before} =
      Sandbox.unboxed_run(Repo, fn ->
        before = Repo.one(MCP.setting_query(tenant))
        user = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil, config: %Brando.Users.UserConfig{})
        app!(tenant, user)
        connect!(tenant, access: "access-1", refresh: "refresh-1", expires_in: 3600)
        {user, before}
      end)

    put_test_env(Brando.Figma, req_options: [plug: {Req.Test, Brando.Figma}], lock_timeout: 5_000)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from e in Brando.Activity.Event, where: e.schema == ^to_string(Setting))
        Repo.delete_all(MCP.setting_query(tenant))
        if before, do: Repo.insert!(before)
        Repo.delete_all(from u in Brando.Users.User, where: u.id == ^user.id)
      end)
    end)

    %{tenant: tenant, user: user}
  end

  # A Figma whose refresh waits for the test to let it answer
  defp stub_slow_refresh do
    test = self()
    counter = :counters.new(1, [])

    stub_figma(fn
      "POST", "/v1/oauth/refresh", _params ->
        :counters.add(counter, 1, 1)
        send(test, {:refreshing, self()})

        receive do
          :answer -> :ok
        after
          5_000 -> :ok
        end

        {200, %{"access_token" => "access-#{:counters.get(counter, 1) + 1}", "expires_in" => 3600}}

      "GET", _path, _params ->
        {200, %{"handle" => "Ada"}}
    end)

    counter
  end

  test "two calls Figma answered 'expired' make one refresh: the second waits on the lock and uses the token the first stored",
       %{tenant: tenant} do
    counter = stub_slow_refresh()

    first = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> OAuth.access_token(tenant, "access-1") end) end)
    assert_receive {:refreshing, first_pid}, 5_000

    # The first holds the row's lock while Figma answers; the second waits
    second = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> OAuth.access_token(tenant, "access-1") end) end)
    await_lock_wait()

    send(first_pid, :answer)
    assert Task.await(first, 10_000) == {:ok, "access-2"}
    assert Task.await(second, 10_000) == {:ok, "access-2"}

    assert :counters.get(counter, 1) == 1
    refute_received {:refreshing, _}

    Sandbox.unboxed_run(Repo, fn ->
      assert decrypted(tenant, :access_token, Repo) == {:ok, "access-2"}
      assert decrypted(tenant, :refresh_token, Repo) == {:ok, "refresh-1"}
    end)
  end

  test "two calls finding the token about to expire make one refresh", %{tenant: tenant} do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.update_all(MCP.setting_query(tenant),
        set: [figma_oauth_expires_at: DateTime.add(DateTime.utc_now(), 60, :second)]
      )
    end)

    counter = stub_slow_refresh()

    first = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> OAuth.access_token(tenant) end) end)
    assert_receive {:refreshing, first_pid}, 5_000
    second = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> OAuth.access_token(tenant) end) end)
    await_lock_wait()

    send(first_pid, :answer)
    assert Task.await(first, 10_000) == {:ok, "access-2"}
    assert Task.await(second, 10_000) == {:ok, "access-2"}
    assert :counters.get(counter, 1) == 1
  end

  test "a call that cannot get the lock in time says to try again in a moment, holding nothing", %{tenant: tenant} do
    put_test_env(Brando.Figma, req_options: [plug: {Req.Test, Brando.Figma}], lock_timeout: 300)
    test = self()

    # Figma answers the call's token "expired", so it needs the lock to renew it
    stub_figma(fn
      "GET", _, _ -> {401, %{"status" => 401, "err" => "Token expired"}}
      "POST", "/v1/oauth/refresh", _ -> {200, %{"access_token" => "never", "expires_in" => 3600}}
    end)

    # Another connection holds the row's lock
    holder =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            Repo.one(from s in MCP.setting_query(tenant), lock: "FOR UPDATE")
            send(test, :locked)

            receive do
              :release -> :ok
            after
              5_000 -> :ok
            end
          end)
        end)
      end)

    assert_receive :locked, 5_000

    started = System.monotonic_time(:millisecond)

    result =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn -> Figma.node({:oauth, tenant}, %{file_key: "k", node_id: "1:2"}) end)
      end)
      |> Task.await(5_000)

    assert result == {:error, "Another call is renewing the site's access to Figma. Try again in a moment."}
    assert System.monotonic_time(:millisecond) - started < 3_000
    refute_received {:figma, "POST", "/v1/oauth/refresh", _, _}

    send(holder.pid, :release)
    Task.await(holder, 5_000)

    # Nothing was marked: the connection is as it was
    assert Sandbox.unboxed_run(Repo, fn -> OAuth.connection_state(tenant) end) == :connected
  end

  test "a call that cannot get the lock in time to renew a token that has not expired goes on with the stored token",
       %{tenant: tenant} do
    put_test_env(Brando.Figma, req_options: [plug: {Req.Test, Brando.Figma}], lock_timeout: 300)
    test = self()

    Sandbox.unboxed_run(Repo, fn ->
      Repo.update_all(MCP.setting_query(tenant),
        set: [figma_oauth_expires_at: DateTime.add(DateTime.utc_now(), 60, :second)]
      )
    end)

    stub_figma(fn
      "POST", "/v1/oauth/refresh", _ -> {200, %{"access_token" => "never", "expires_in" => 3600}}
      "GET", _, _ -> {200, %{"name" => "File", "nodes" => %{"1:2" => %{"document" => %{"id" => "1:2", "type" => "FRAME"}}}}}
    end)

    holder =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            Repo.one(from s in MCP.setting_query(tenant), lock: "FOR UPDATE")
            send(test, :locked)

            receive do
              :release -> :ok
            after
              5_000 -> :ok
            end
          end)
        end)
      end)

    assert_receive :locked, 5_000

    result =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn -> Figma.node({:oauth, tenant}, %{file_key: "k", node_id: "1:2"}) end)
      end)
      |> Task.await(5_000)

    assert {:ok, %{file_name: "File"}} = result
    assert_received {:figma, "GET", _, _, %{"authorization" => "Bearer access-1"}}
    refute_received {:figma, "POST", "/v1/oauth/refresh", _, _}

    send(holder.pid, :release)
    Task.await(holder, 5_000)
  end

  test "a renewal that outlasts the database's hold on the transaction says to try again, keeping the refresh token",
       %{tenant: tenant} do
    # Limits shrunk so the test need not wait: the transaction is given
    # twice the lock wait and Figma's connect and receive limits together
    put_test_env(Brando.Figma,
      req_options: [plug: {Req.Test, Brando.Figma}],
      lock_timeout: 100,
      connect_timeout: 100,
      receive_timeout: 100
    )

    Sandbox.unboxed_run(Repo, fn ->
      Repo.update_all(MCP.setting_query(tenant),
        set: [figma_oauth_expires_at: DateTime.add(DateTime.utc_now(), -60, :second)]
      )
    end)

    slow_refresh = fn wait ->
      stub_figma(fn "POST", "/v1/oauth/refresh", _ ->
        Process.sleep(wait)
        {200, %{"access_token" => "access-#{wait}", "refresh_token" => "refresh-#{wait}", "expires_in" => 60}}
      end)
    end

    # Longer than the lock wait and Figma's limits together, but within the
    # transaction's: saved
    slow_refresh.(400)
    assert Sandbox.unboxed_run(Repo, fn -> OAuth.access_token(tenant, "access-1") end) == {:ok, "access-400"}

    # Past the transaction's: nothing saved, and the call says to try again
    slow_refresh.(1_000)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        result = Sandbox.unboxed_run(Repo, fn -> OAuth.access_token(tenant, "access-400") end)
        send(self(), {:result, result})
      end)

    assert_received {:result, {:error, :unreachable}}
    refute log =~ "refresh-400"
    refute log =~ "access-400"

    Sandbox.unboxed_run(Repo, fn ->
      assert OAuth.connection_state(tenant) == :connected
      assert decrypted(tenant, :access_token, Repo) == {:ok, "access-400"}
      assert decrypted(tenant, :refresh_token, Repo) == {:ok, "refresh-400"}
    end)
  end

  test "a callback that cannot get the row's lock in time saves nothing, says to try again, and leaves the attempt",
       %{tenant: tenant, user: user} do
    put_test_env(Brando.Figma, req_options: [plug: {Req.Test, Brando.Figma}], lock_timeout: 300)
    test = self()

    {:ok, url} = Sandbox.unboxed_run(Repo, fn -> OAuth.disconnect(tenant, user) && OAuth.start(tenant, user, 7) end)
    state = URI.decode_query(URI.parse(url).query)["state"]
    stub_figma(fn _, _, _ -> {500, %{}} end)

    holder =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            Repo.one(from s in MCP.setting_query(tenant), lock: "FOR UPDATE")
            send(test, :locked)

            receive do
              :release -> :ok
            after
              5_000 -> :ok
            end
          end)
        end)
      end)

    assert_receive :locked, 5_000
    started = System.monotonic_time(:millisecond)

    finishing =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn -> OAuth.finish(%{"state" => state, "code" => "code-1"}, user, 7) end)
      end)

    assert Task.yield(finishing, 3_000) == {:ok, {:error, :save_failed, nil}}
    assert System.monotonic_time(:millisecond) - started < 3_000
    refute_received {:figma, _, _, _, _}

    send(holder.pid, :release)
    Task.await(holder, 5_000)

    Sandbox.unboxed_run(Repo, fn ->
      assert OAuth.connection_state(tenant) == :none
      refute is_nil(setting(tenant, Repo).figma_oauth_state_hash)
    end)
  end

  test "a connection that cannot be saved in time saves nothing, and says to try again", %{tenant: tenant, user: user} do
    put_test_env(Brando.Figma, req_options: [plug: {Req.Test, Brando.Figma}], lock_timeout: 300)
    test = self()

    {:ok, url} = Sandbox.unboxed_run(Repo, fn -> OAuth.disconnect(tenant, user) && OAuth.start(tenant, user, 7) end)
    state = URI.decode_query(URI.parse(url).query)["state"]

    stub_figma(fn
      "POST", "/v1/oauth/token", _ ->
        {200, %{"access_token" => "access-9", "refresh_token" => "refresh-9", "expires_in" => 60}}

      "GET", "/v1/me", _ ->
        # Another connection takes the row's lock before the save
        send(test, :take_lock)
        assert_receive :locked, 5_000
        {200, %{"handle" => "Ada"}}
    end)

    holder =
      Task.async(fn ->
        receive do
          :take_lock -> :ok
        end

        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            Repo.one(from s in MCP.setting_query(tenant), lock: "FOR UPDATE")
            send(test, {:locked, self()})

            receive do
              :release -> :ok
            after
              5_000 -> :ok
            end
          end)
        end)
      end)

    finishing =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn -> OAuth.finish(%{"state" => state, "code" => "code-1"}, user, 7) end)
      end)

    assert_receive :take_lock, 5_000
    send(holder.pid, :take_lock)
    assert_receive {:locked, _holder}, 5_000
    send(finishing.pid, :locked)

    assert {:error, :save_failed, _tenant} = Task.await(finishing, 5_000)
    send(holder.pid, :release)
    Task.await(holder, 5_000)

    Sandbox.unboxed_run(Repo, fn ->
      assert OAuth.connection_state(tenant) == :none
      assert no_connection?(tenant, Repo)
    end)
  end

  # Until another connection waits on a row lock on mcp_settings
  defp await_lock_wait(tries \\ 100) do
    waiting =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("""
        SELECT count(*) FROM pg_stat_activity
        WHERE datname = current_database() AND wait_event_type = 'Lock' AND query LIKE '%mcp_settings%'
        """).rows
      end)

    cond do
      waiting == [[1]] ->
        :ok

      tries == 0 ->
        flunk("nothing ever waited on the row lock")

      true ->
        Process.sleep(20)
        await_lock_wait(tries - 1)
    end
  end
end

defmodule Brando.MCP.OAuthConcurrencyTest do
  # Two refreshes of the same refresh token on two real connections, the
  # second waiting on the row lock the first holds. Outside the sandbox, so
  # that the lock and the commit between them are real.
  use ExUnit.Case, async: false

  import Brando.MCPHelpers
  import Ecto.Query, only: [from: 2]

  alias Brando.MCP
  alias Brando.MCP.Grant
  alias Brando.MCP.OAuth
  alias Brando.MCP.Setting
  alias Brando.MCP.Token
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @handler __MODULE__

  setup do
    tenant = MCP.tenant(nil, nil)
    refresh_token = "bmcp_rt_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    {user, grant, setting} =
      Sandbox.unboxed_run(Repo, fn ->
        setting = Repo.one(from s in Setting, where: is_nil(s.site_id) and is_nil(s.environment_id))
        user = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil, config: %Brando.Users.UserConfig{})
        enable_two_factor(user)
        switch!(tenant)

        grant =
          Repo.insert!(%Grant{
            user_id: user.id,
            resource: MCP.resource(tenant),
            client_id: client_id(),
            client_name: "Test Client",
            redirect_uri: redirect_uri(),
            scope: MCP.scope()
          })

        Repo.insert!(%Token{
          grant_id: grant.id,
          kind: :refresh,
          token_hash: OAuth.hash(refresh_token),
          expires_at: DateTime.add(DateTime.utc_now(), 86_400, :second)
        })

        {user, grant, setting}
      end)

    on_exit(fn ->
      :telemetry.detach(@handler)

      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from e in Brando.Activity.Event, where: e.schema == ^to_string(Grant) and e.entry_id == ^grant.id)
        Repo.delete_all(from e in Brando.Users.SecurityEvent, where: e.user_id == ^user.id)
        # Takes its grant, tokens and two-factor row with it
        Repo.delete_all(from u in Brando.Users.User, where: u.id == ^user.id)

        case setting do
          nil -> Repo.delete_all(from s in Setting, where: is_nil(s.site_id) and is_nil(s.environment_id))
          %Setting{enabled: enabled} -> switch!(tenant, enabled)
        end
      end)
    end)

    params = %{"grant_type" => "refresh_token", "refresh_token" => refresh_token, "client_id" => client_id()}
    %{tenant: tenant, grant: grant, params: params}
  end

  test "a second refresh waiting on the first one's row lock gets the same pair, and the connection stays", %{
    tenant: tenant,
    grant: grant,
    params: params
  } do
    :ok =
      :telemetry.attach(@handler, Repo.config()[:telemetry_prefix] ++ [:query], &__MODULE__.pause_at/4, nil)

    parent = self()

    first =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Process.put(@handler, parent)
          OAuth.token(params, tenant)
        end)
      end)

    # The first has rotated the token and holds its row lock
    assert_receive {:paused, :rotated, first_pid}, 5_000

    second = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> OAuth.token(params, tenant) end) end)
    await_lock_wait()

    # The first commits, and stops right after, before anything that runs
    # once the transaction has returned; the second gets the lock now
    send(first_pid, {:resume, :rotated})
    assert_receive {:paused, :committed, ^first_pid}, 5_000
    second_answer = Task.await(second, 10_000)

    send(first_pid, {:resume, :committed})
    assert {:ok, pair} = Task.await(first, 10_000)

    assert second_answer == {:ok, pair}

    Sandbox.unboxed_run(Repo, fn ->
      assert %Grant{revoked_at: nil} = Repo.get!(Grant, grant.id)
      assert %Token{revoked_at: nil, rotated_at: nil} = Repo.get_by!(Token, token_hash: OAuth.hash(pair["refresh_token"]))
      assert %Token{revoked_at: nil} = Repo.get_by!(Token, token_hash: OAuth.hash(pair["access_token"]))
    end)
  end

  # Telemetry handler, run in the process that made the query: in the first
  # refresh's process only, it stops once after the token's rotation and
  # once after the commit, until the test lets it go on.
  @doc false
  def pause_at(_event, _measurements, metadata, _config) do
    with test_pid when is_pid(test_pid) <- Process.get(@handler),
         point when not is_nil(point) <- pause_point(metadata),
         false <- Process.get({@handler, point}, false) do
      Process.put({@handler, point}, true)
      send(test_pid, {:paused, point, self()})

      receive do
        {:resume, ^point} -> :ok
      after
        10_000 -> :ok
      end
    end

    :ok
  end

  defp pause_point(%{source: "mcp_tokens", query: "UPDATE" <> _}), do: :rotated
  defp pause_point(%{query: "commit"}), do: :committed
  defp pause_point(_metadata), do: nil

  # Until another connection waits on a row lock on mcp_tokens
  defp await_lock_wait(tries \\ 100) do
    waiting =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("""
        SELECT count(*) FROM pg_stat_activity
        WHERE datname = current_database() AND wait_event_type = 'Lock' AND query LIKE '%mcp_tokens%'
        """).rows
      end)

    cond do
      waiting == [[1]] ->
        :ok

      tries == 0 ->
        flunk("the second refresh never waited on the row lock")

      true ->
        Process.sleep(20)
        await_lock_wait(tries - 1)
    end
  end
end

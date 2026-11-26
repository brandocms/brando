defmodule Brando.Crypto.Audit do
  @moduledoc """
  What this installation's secret (`Brando.Crypto`) cannot read in the
  database, and the clean-up that forgets it.

  `run/0` counts, across `public` and every site environment, archived and
  suspended sites' included:

    * `:users` whose two-factor secret does not decrypt;
    * `:webhooks` and `:notification_routes` whose secret or webhook URL does
      not decrypt, among those that send or resume by themselves (active, or
      paused for an environment copy, which resume when it goes live). An
      email route stores no URL and is never counted;
    * the Figma credentials of `Brando.MCP.Setting`, as four groups:
      `:figma_token` (a pasted token), `:figma_app` (the OAuth app),
      `:figma_connection` (the OAuth connection) and `:figma_pending` (a
      connection being made).

  Decryption is authenticated, so each count is exact. Keyed hashes cannot
  be tested: recovery codes and passkeys are not counted. Short-lived values
  (MCP OAuth replay data, translation work tokens) are not listed.

  `forget/2` forgets what `run/0` counts, and nothing that decrypts. Rows
  are read in batches, so thousands of users or webhooks are never in memory
  at once.
  """
  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Crypto.Marker
  alias Brando.MCP.Setting
  alias Brando.Notifications.Routing
  alias Brando.Repo
  alias Brando.Users.Security
  alias Brando.Users.TwoFactor
  alias Brando.Webhooks

  require Logger

  @batch_size 500

  @type counts :: %{
          users: non_neg_integer(),
          webhooks: non_neg_integer(),
          notification_routes: non_neg_integer(),
          figma_token: non_neg_integer(),
          figma_app: non_neg_integer(),
          figma_connection: non_neg_integer(),
          figma_pending: non_neg_integer()
        }

  @kinds [:users, :webhooks, :notification_routes, :figma_token, :figma_app, :figma_connection, :figma_pending]

  @doc "The kinds `run/0` counts, in the order to show them."
  @spec kinds() :: [atom()]
  def kinds, do: @kinds

  @doc "How many values of each kind this secret cannot read. Reads only."
  @spec run() :: counts()
  def run do
    outbound =
      Enum.reduce(prefixes(), %{webhooks: 0, notification_routes: 0}, fn prefix, acc ->
        %{
          webhooks: acc.webhooks + Webhooks.count_unreadable(prefix),
          notification_routes: acc.notification_routes + Routing.count_unreadable(prefix)
        }
      end)

    figma =
      reduce_settings(%{figma_token: 0, figma_app: 0, figma_connection: 0, figma_pending: 0}, fn setting, acc ->
        acc
        |> bump(:figma_token, Brando.MCP.figma_token_unreadable?(setting))
        |> count_groups(Brando.Figma.OAuth.unreadable_groups(setting))
      end)

    %{users: reduce_users(0, fn _user_id, _ciphertext, count -> count + 1 end)}
    |> Map.merge(outbound)
    |> Map.merge(figma)
  end

  @doc "Whether `counts` has anything this secret cannot read."
  @spec unreadable?(counts()) :: boolean()
  def unreadable?(counts), do: Enum.any?(@kinds, &(Map.get(counts, &1, 0) > 0))

  @doc """
  The schemas that hold webhooks and notification routes: nil for `public`,
  then the prefix of every environment of every site, whatever the site's
  status. Without tenancy, `public` only.
  """
  @spec prefixes() :: [String.t() | nil]
  def prefixes do
    if Brando.Tenant.enabled?() do
      environments =
        for site <- Brando.Tenant.Registry.list_sites(), environment <- site.environments do
          Brando.Tenant.prefix(site, environment)
        end

      [nil | environments]
    else
      [nil]
    end
  end

  ## The clean-up

  @doc """
  Forgets what this installation's secret cannot read, as `actor`: `:system`
  (`Brando.Release.forget_unreadable/0`), or a user who may reset any other
  user's two-factor authentication (a superuser; `{:error, :forbidden}`
  otherwise).

    * Each user whose two-factor secret does not decrypt has it reset as
      `Brando.Users.TwoFactor.reset/3` does, passkeys excepted, each in a
      transaction of their own. `opts[:keep_id]` is the token row of the
      session `actor` runs it from, which stays.
    * The webhooks and notification routes `run/0` counts are paused by hand,
      their secrets kept.
    * Each Figma group that does not decrypt is removed as the admin removes
      it; the others stay.

  Every change is made only while the value is still the one that did not
  decrypt, so a user who sets two-factor authentication up again, a webhook
  given a new secret or a Figma callback that lands meanwhile is never
  undone. Then the marker (`Brando.Crypto.Marker`) is written, only when
  every part succeeded: run it again to finish one that failed. Safe to run
  twice and to interrupt.

  Returns `{:ok, result}`: the counts of what it forgot, `:failed` (the parts
  that failed: `:users`, `:figma`, or a schema, `"public"` or a prefix) and
  `:marker` (`:written` or `:kept`).
  """
  @spec forget(map() | :system, keyword()) :: {:ok, map()} | {:error, :forbidden}
  def forget(actor, opts \\ []) do
    if actor == :system or Boundary.superuser?(actor),
      do: {:ok, do_forget(actor, opts)},
      else: {:error, :forbidden}
  end

  defp do_forget(actor, opts) do
    {users, failed} =
      attempt(:users, 0, [], fn ->
        reduce_users(0, fn user_id, ciphertext, count ->
          if TwoFactor.forget_unreadable(user_id, ciphertext, actor, keep_id: opts[:keep_id]),
            do: count + 1,
            else: count
        end)
      end)

    {outbound, failed} =
      Enum.reduce(prefixes(), {%{webhooks: 0, notification_routes: 0}, failed}, fn prefix, {acc, failed} ->
        {counts, failed} =
          attempt(prefix || "public", %{webhooks: 0, notification_routes: 0}, failed, fn ->
            # A schema's pauses commit together, or not at all
            {:ok, counts} =
              Repo.transaction(fn ->
                %{
                  webhooks: Webhooks.pause_unreadable(prefix, actor),
                  notification_routes: Routing.pause_unreadable(prefix, actor)
                }
              end)

            counts
          end)

        {Map.merge(acc, counts, fn _kind, a, b -> a + b end), failed}
      end)

    empty_figma = %{figma_token: 0, figma_app: 0, figma_connection: 0, figma_pending: 0}

    {figma, failed} =
      attempt(:figma, empty_figma, failed, fn ->
        reduce_settings(empty_figma, fn setting, acc ->
          acc
          |> bump(:figma_token, Brando.MCP.forget_unreadable_figma_token(setting, actor))
          |> count_groups(Brando.Figma.OAuth.forget_unreadable(setting, actor))
        end)
      end)

    marker = if failed == [], do: write_marker(), else: :kept

    %{users: users}
    |> Map.merge(outbound)
    |> Map.merge(figma)
    |> Map.merge(%{failed: Enum.reverse(failed), marker: marker})
  end

  defp write_marker do
    :ok = Marker.write()
    :written
  end

  # A part that fails is logged and left for a second run; the others go on
  defp attempt(part, empty, failed, fun) do
    {fun.(), failed}
  rescue
    error ->
      Logger.error("[Brando.Crypto.Audit] Could not clean up #{part}: " <> Exception.message(error))
      {empty, [part | failed]}
  end

  ## Reading in batches

  # Users with a two-factor secret that does not decrypt, by user id
  defp reduce_users(acc, fun), do: reduce_users(0, acc, fun)

  defp reduce_users(after_id, acc, fun) do
    batch =
      Repo.all(
        from(s in Security,
          where: s.user_id > ^after_id and not is_nil(s.totp_secret),
          order_by: s.user_id,
          limit: @batch_size,
          select: {s.user_id, s.totp_secret}
        )
      )

    acc =
      batch
      |> Enum.reject(fn {user_id, ciphertext} -> TwoFactor.readable_secret?(user_id, ciphertext) end)
      |> Enum.reduce(acc, fn {user_id, ciphertext}, acc -> fun.(user_id, ciphertext, acc) end)

    case List.last(batch) do
      {last, _ciphertext} when length(batch) == @batch_size -> reduce_users(last, acc, fun)
      _ -> acc
    end
  end

  # MCP settings rows, with their site and environment
  defp reduce_settings(acc, fun) do
    if mcp_settings?(), do: reduce_settings(0, acc, fun), else: acc
  end

  defp reduce_settings(after_id, acc, fun) do
    batch =
      Repo.all(
        from(s in Setting, where: s.id > ^after_id, order_by: s.id, limit: @batch_size, preload: [:site, :environment])
      )

    acc = Enum.reduce(batch, acc, fun)

    case List.last(batch) do
      %Setting{id: last} when length(batch) == @batch_size -> reduce_settings(last, acc, fun)
      _ -> acc
    end
  end

  defp mcp_settings? do
    %{rows: [[table]]} = Repo.repo().query!("SELECT to_regclass('public.mcp_settings')::text")
    not is_nil(table)
  end

  defp bump(acc, kind, true), do: Map.update!(acc, kind, &(&1 + 1))
  defp bump(acc, _kind, _false), do: acc

  defp count_groups(acc, groups) do
    acc
    |> bump(:figma_app, :app in groups)
    |> bump(:figma_connection, :connection in groups)
    |> bump(:figma_pending, :pending in groups)
  end
end

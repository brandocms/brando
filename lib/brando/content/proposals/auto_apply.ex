defmodule Brando.Content.Proposals.AutoApply do
  @moduledoc """
  Applying a connected tool's proposal without review, where its connection
  allows it (`Brando.MCP.Grant`'s `auto_apply`, set by the site's managers).

  The one kind is `"unpublished_translations"`: a proposal whose stored
  operations are each a `create_translation`, or a `translate` of a
  translation another operation of the same proposal creates
  (`{"new": ref}`), and nothing else. Whether a proposal qualifies is read
  from its frozen operations on the server, never from what the tool says.

  A tool asks for it with `apply: "if_allowed"` in `prepare_proposal`. The
  proposal is stored and committed first, as any proposal is, and then
  applied by `Brando.Content.Proposals.apply/4` as the connection's user,
  with their permissions at that moment: the same locks, staleness checks,
  validation and Activity as an approval in the admin, without an approval.
  Inside the apply's transaction:

    * the endpoint's switch and the connection are locked and checked by
      the rule that authorizes each request (`Brando.MCP.lock_auto_apply/3`),
      so turning the setting off, revoking the connection or turning the
      endpoint off, committed first, applies nothing, and one that comes
      later waits for the apply. Losing Connect (a group, role or site
      assignment) or the site being suspended takes no lock: what is
      committed when the apply checks it counts;
    * the user must still be allowed to review proposals (Assistant → Use);
    * every entry the proposal created must come out a draft with no
      publishing date ahead. A context's own save could publish it, and a
      content type without a status never qualifies.

  When any of it fails, nothing of the attempt is kept: the proposal stays
  pending, unapproved, for the person to review, with the reason in
  `auto_apply_reason`, apart from its problems. Applied, the proposal keeps
  the connection's id in `auto_applied_grant_id`.

  Only a call that a connection authenticated can apply this way: the
  Assistant and the development stdio server have none.
  """
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Proposals.Receipt
  alias Brando.Content.Proposals.Record
  alias Brando.Content.Transfer.Error
  alias Brando.MCP
  alias Brando.Repo

  require Logger

  @kind "unpublished_translations"

  @doc "The kind of proposal a connection may apply without review."
  @spec kind() :: String.t()
  def kind, do: @kind

  @doc """
  Whether stored (frozen) `operations` only create translations: each is a
  `create_translation`, or a `translate` of `{"new": ref}` where `ref` is a
  translation this proposal creates. An empty list does not qualify.
  """
  @spec qualifies?([map()] | nil) :: boolean()
  def qualifies?([_ | _] = operations) do
    refs = for %{"op" => "create_translation", "ref" => ref} <- operations, do: ref

    Enum.all?(operations, fn
      %{"op" => "create_translation"} -> true
      %{"op" => "translate", "target" => %{"new" => ref}} -> ref in refs
      _ -> false
    end)
  end

  def qualifies?(_operations), do: false

  @doc """
  Applies the stored version `version` of proposal `id` without review,
  as `actor`, under the connection `grant_id` at `tenant`, and says what is
  stored after the attempt, whatever the attempt returned:

    * `{:applied, receipt}`: applied under this connection;
    * `{:waiting, reason}`: still under review, and `reason` says why it was
      not applied, in a sentence a tool can act on;
    * `{:settled, status, reason}`: the person settled it in the admin
      meanwhile (cancelled or applied it), or a newer version replaced it.

  Never raises: a crash reads what is stored too.
  """
  @spec run(Ecto.UUID.t(), pos_integer(), term(), integer() | nil, MCP.tenant() | nil) ::
          {:applied, Receipt.t()}
          | {:waiting, String.t()}
          | {:settled, String.t(), String.t()}
  def run(id, version, _actor, grant_id, tenant) when is_nil(grant_id) or is_nil(tenant),
    do: outcome(id, version, grant_id, no_connection())

  def run(id, version, actor, grant_id, tenant) do
    reason =
      try do
        case Brando.Content.Proposals.apply(id, version, actor, auto: %{grant_id: grant_id, tenant: tenant}) do
          {:ok, _receipt} -> failed()
          {:error, message} -> reason(message)
        end
      rescue
        exception ->
          Logger.error("[Brando.Content.Proposals.AutoApply] Applying #{id} failed: " <> Exception.message(exception))
          failed()
      end

    outcome(id, version, grant_id, reason)
  end

  # The apply's own refusal (content changed, a validation) is said as why
  # it was not applied
  defp reason(message) do
    if message in [no_connection(), not_allowed(), not_qualified(), cannot_review(), would_publish()],
      do: message,
      else:
        dgettext("content_proposals", "It was not applied automatically: %{reason} It waits for review.", reason: message)
  end

  # What is stored decides. Under review still: the reason is kept on that
  # version, apart from its problems.
  defp outcome(id, version, grant_id, reason) do
    case Repo.update_all(
           from(r in Record, where: r.id == ^id and r.version == ^version and r.status in ~w(pending approved)),
           set: [auto_apply_reason: reason]
         ) do
      {1, _} -> {:waiting, reason}
      {0, _} -> settled(id, version, grant_id)
    end
  end

  defp settled(id, version, grant_id) do
    case Repo.one(from(r in Record, where: r.id == ^id, select: {r.version, r.status, r.auto_applied_grant_id})) do
      {^version, "applied", ^grant_id} when is_integer(grant_id) ->
        {:applied, Repo.one!(from(r in Receipt, where: r.id == ^id))}

      {_version, status, _grant_id} ->
        {:settled, status, settled_reason(status)}

      nil ->
        {:settled, "cancelled", settled_reason("cancelled")}
    end
  end

  defp settled_reason(status),
    do:
      dgettext(
        "content_proposals",
        "It was not applied automatically: meanwhile it became %{status}. Call list_proposals to see where it stands.",
        status: status
      )

  @doc """
  Inside `Brando.Content.Proposals.apply/4`, before anything is locked:
  raises unless the stored `record`'s operations qualify (`qualifies?/1`).
  """
  @spec qualify!(Record.t()) :: :ok
  def qualify!(%Record{operations: operations}) do
    unless qualifies?(operations), do: Error.fail!(not_qualified())
    :ok
  end

  @doc """
  Inside the apply's transaction: locks the connection until the commit and
  raises unless it may apply this kind now (`Brando.MCP.lock_auto_apply/3`)
  and `actor` may still review proposals (Assistant → Use).
  """
  @spec authorize!(%{grant_id: integer(), tenant: MCP.tenant()}, term()) :: :ok
  def authorize!(%{grant_id: grant_id, tenant: tenant}, actor) do
    case MCP.lock_auto_apply(grant_id, @kind, tenant) do
      {:ok, _grant} -> :ok
      {:error, :not_allowed} -> Error.fail!(not_allowed())
      {:error, _reason} -> Error.fail!(no_connection())
    end

    unless Brando.AI.Agent.allowed?(actor), do: Error.fail!(cannot_review())
    :ok
  end

  @doc """
  After every operation ran, before the commit: raises unless each entry
  the proposal created (`{:new, ref}` in `saved`) is a draft with no
  publishing date ahead. A content type without a status never is.
  """
  @spec unpublished!([{term(), struct(), term()}]) :: :ok
  def unpublished!(saved) do
    now = DateTime.utc_now()

    for {{:new, _ref}, %schema{id: id}, _cs} <- saved,
        not (schema.has_trait(Brando.Trait.Status) and draft?(Repo.get(schema, id), now)) do
      Error.fail!(would_publish())
    end

    :ok
  end

  defp draft?(%{status: :draft} = entry, now), do: not scheduled?(Map.get(entry, :publish_at), now)
  defp draft?(_entry, _now), do: false

  defp scheduled?(%DateTime{} = publish_at, now), do: DateTime.after?(publish_at, now)
  defp scheduled?(_publish_at, _now), do: false

  defp failed,
    do: dgettext("content_proposals", "It was not applied automatically: applying it failed. It waits for review.")

  defp no_connection,
    do:
      dgettext(
        "content_proposals",
        "It was not applied automatically: only a connected tool, on a connection that is still allowed to, can apply without review. It waits for review."
      )

  defp not_allowed,
    do:
      dgettext(
        "content_proposals",
        "It was not applied automatically: this connection is not set to apply unpublished translations without review. It waits for review; a site manager can change that under Configuration → Integrations → Connected AI tools."
      )

  defp not_qualified,
    do:
      dgettext(
        "content_proposals",
        "It was not applied automatically: only a proposal whose every operation is create_translation, or translate of a translation it creates ({\"new\": ref}), is. It waits for review."
      )

  defp cannot_review,
    do:
      dgettext(
        "content_proposals",
        "It was not applied automatically: the person may not review proposals (Assistant → Use). It waits for review."
      )

  defp would_publish,
    do:
      dgettext(
        "content_proposals",
        "It was not applied automatically: a translation it creates would not be an unpublished draft. It waits for review."
      )
end

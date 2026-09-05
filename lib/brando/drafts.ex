defmodule Brando.Drafts do
  @moduledoc "Durable recovery storage, independent of Blueprint schemas and the editor."
  import Ecto.Query, only: [from: 2]
  alias Brando.Drafts.EntryDraft
  alias Brando.Repo
  alias Ecto.Changeset

  def scope, do: Brando.Tenant.current_prefix() || "public"

  def identity(schema, entry_id, owner_id, form_name \\ :default) do
    %{
      scope: scope(),
      owner_id: owner_id,
      entry_type: to_string(schema),
      entry_id: entry_id,
      form_name: to_string(form_name)
    }
  end

  def list(identity) do
    identity
    |> owned_query()
    |> then(fn query ->
      from d in query,
        where: is_nil(d.resolved_at) and is_nil(d.discarded_at) and d.expires_at > ^DateTime.utc_now(),
        order_by: [desc: d.updated_at]
    end)
    |> Repo.all()
  end

  def get(identity, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      Repo.one(from d in owned_query(identity), where: d.id == ^uuid and d.expires_at > ^DateTime.utc_now())
    else
      _ -> nil
    end
  end

  # Serialize writes with resolve/discard so late captures cannot resurrect a
  # saved or dismissed recovery copy. Generation also rejects out-of-order replies.
  def write(identity, id, generation, payload, base_fingerprint, schema_version) do
    checksum = checksum(payload)
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      lock(id)
      existing = Repo.one(from d in EntryDraft, where: d.id == ^id, lock: "FOR UPDATE")

      cond do
        existing && not owned?(existing, identity) ->
          Repo.rollback(:not_found)

        existing && (existing.resolved_at || existing.discarded_at || existing.attempted_at) ->
          Repo.rollback(:closed)

        existing && existing.generation >= generation ->
          existing

        true ->
          attrs =
            Map.merge(identity, %{
              id: id,
              generation: generation,
              payload: payload,
              checksum: checksum,
              base_fingerprint: base_fingerprint,
              schema_version: schema_version,
              expires_at: DateTime.add(now, retention_days() * 86_400, :second)
            })

          if existing && existing.checksum == checksum do
            existing |> Changeset.change(Map.take(attrs, [:generation, :expires_at])) |> Repo.update!()
          else
            (existing || %EntryDraft{}) |> Changeset.change(attrs) |> Repo.repo().insert_or_update!(prefix: "public")
          end
      end
    end)
  end

  def dismiss(identity, id), do: mark(identity, id, dismissed_at: DateTime.utc_now())

  def begin_restore(identity, id) do
    now = DateTime.utc_now()
    mark(identity, id, attempted_at: now, dismissed_at: now)
  end

  def discard(identity, id) do
    now = DateTime.utc_now()

    mark(identity, id,
      discarded_at: now,
      dismissed_at: now,
      expires_at: DateTime.add(now, resolved_days() * 86_400, :second)
    )
  end

  def resolve(identity, id, generation) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      lock(id)
      expires = DateTime.add(now, resolved_days() * 86_400, :second)

      case Repo.one(from d in EntryDraft, where: d.id == ^id, lock: "FOR UPDATE") do
        nil ->
          attrs =
            Map.merge(identity, %{
              id: id,
              generation: generation,
              base_fingerprint: "",
              payload: %{},
              checksum: checksum(%{}),
              schema_version: 0,
              resolved_at: now,
              expires_at: expires
            })

          %EntryDraft{} |> Changeset.change(attrs) |> Repo.insert!()

        %{generation: current} = draft when current <= generation ->
          if owned?(draft, identity),
            do: draft |> Changeset.change(resolved_at: now, expires_at: expires) |> Repo.update!(),
            else: Repo.rollback(:not_found)

        draft ->
          if owned?(draft, identity), do: draft, else: Repo.rollback(:not_found)
      end
    end)
  end

  def purge do
    Repo.delete_all(from d in EntryDraft, where: d.expires_at < ^DateTime.utc_now())
  end

  def rebind_entry(identity, id, entry_id) do
    query = from d in owned_query(identity), where: d.id == ^id
    Repo.update_all(query, set: [entry_id: entry_id])
  end

  def checksum(value),
    do:
      value |> canonical() |> :erlang.term_to_binary() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

  def fingerprint(entry) do
    checksum(%{
      identity: Map.take(entry, [:id, :updated_at, :version, :lock_version]),
      content: Brando.Drafts.Params.snapshot(entry)
    })
  end

  defp canonical(%_{} = value), do: value |> Map.from_struct() |> canonical()

  defp canonical(value) when is_map(value),
    do: value |> Enum.map(fn {k, v} -> {to_string(k), canonical(v)} end) |> Enum.sort()

  defp canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  defp canonical(value), do: value

  defp retention_days, do: Application.get_env(:brando, :draft_retention_days, 30)
  defp resolved_days, do: Application.get_env(:brando, :resolved_draft_retention_days, 7)

  defp owned_query(identity) do
    Enum.reduce(identity, from(d in EntryDraft, select: d), fn
      {key, nil}, query -> from d in query, where: is_nil(field(d, ^key))
      {key, value}, query -> from d in query, where: field(d, ^key) == ^value
    end)
  end

  defp owned?(draft, identity), do: Enum.all?(identity, fn {key, value} -> Map.get(draft, key) == value end)

  defp mark(identity, id, attrs) do
    Repo.transaction(fn ->
      lock(id)

      case get(identity, id) do
        nil -> Repo.rollback(:not_found)
        %{resolved_at: nil, discarded_at: nil} = draft -> draft |> Changeset.change(attrs) |> Repo.update!()
        _ -> Repo.rollback(:closed)
      end
    end)
  end

  defp lock(id),
    do: Ecto.Adapters.SQL.query!(Repo.repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 2694))", [id])
end

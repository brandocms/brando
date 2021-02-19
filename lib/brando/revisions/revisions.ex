defmodule Brando.Revisions do
  alias Brando.Revisions.Revision
  import Ecto.Query

  def create_revision(%{__struct__: entry_type, id: entry_id} = entry, user) do
    user_id = if user == :system, do: nil, else: user.id
    entry_type_binary = to_string(entry_type)
    encoded_entry = encode_entry(entry)

    revision = %{
      active: true,
      entry_type: entry_type_binary,
      entry_id: entry_id,
      encoded_entry: encoded_entry,
      metadata: %{},
      revision: next_revision(entry_type_binary, entry_id),
      creator_id: user_id,
      protected: false
    }

    %Revision{}
    |> Revision.changeset(revision)
    |> Brando.repo().insert()
    |> case do
      {:ok, revision} ->
        # set all others as inactive
        set_all_inactive_except(revision)

        {:ok, revision}

      err ->
        err
    end
  end

  defp set_all_inactive_except(revision) do
    query =
      from r in Revision,
        where:
          r.active == true and
            r.entry_type == ^revision.entry_type and
            r.entry_id == ^revision.entry_id and
            r.revision != ^revision.revision,
        update: [set: [active: false]]

    Brando.repo().update_all(query, [])
  end

  defp set_active(revision) do
    query =
      from r in Revision,
        where:
          r.entry_type == ^revision.entry_type and
            r.entry_id == ^revision.entry_id and
            r.revision == ^revision.revision,
        update: [set: [active: true]]

    Brando.repo().update_all(query, [])
  end

  def get_last_revision(%{__struct__: entry_type, id: entry_id}) do
    entry_type_binary = to_string(entry_type)

    query =
      from r in Revision,
        where: r.entry_type == ^entry_type_binary and r.entry_id == ^entry_id,
        limit: 1,
        order_by: [desc: :revision]

    case Brando.repo().all(query) do
      [] ->
        :error

      [revision] ->
        decoded_entry = decode_entry(revision.encoded_entry)
        {:ok, {revision, {revision.revision, decoded_entry}}}
    end
  end

  def set_revision(entry, revision_number) do
    {:ok, {revision, {_revision_number, decoded_entry}}} = get_revision(entry, revision_number)

    do_set_revision(entry, decoded_entry, revision)
  end

  def set_last_revision(entry) do
    {:ok, {revision, {_revision_number, decoded_entry}}} = get_last_revision(entry)

    do_set_revision(entry, decoded_entry, revision)
  end

  defp do_set_revision(%{__struct__: entry_type, id: _entry_id} = entry, decoded_entry, revision) do
    entry
    |> entry_type.changeset(Map.delete(Map.from_struct(decoded_entry), :__meta__))
    |> Brando.repo().update
    |> case do
      {:ok, new_entry} ->
        set_active(revision)
        set_all_inactive_except(revision)

        {:ok, new_entry}

      err ->
        err
    end
  end

  def get_revision(%{__struct__: entry_type, id: entry_id}, revision_number) do
    entry_type_binary = to_string(entry_type)

    query =
      from r in Revision,
        where:
          r.entry_type == ^entry_type_binary and
            r.entry_id == ^entry_id and
            r.revision == ^revision_number,
        limit: 1,
        order_by: [desc: :revision]

    case Brando.repo().all(query) do
      [] ->
        :error

      [revision] ->
        decoded_entry = decode_entry(revision.encoded_entry)
        {:ok, {revision, {revision.revision, decoded_entry}}}
    end
  end

  defp encode_entry(entry) do
    :erlang.term_to_binary(entry, compressed: 9)
  end

  defp decode_entry(binary) do
    :erlang.binary_to_term(binary)
  end

  defp next_revision(entry_type, entry_id) do
    query =
      from r in Revision,
        select: r.revision,
        where: r.entry_type == ^entry_type and r.entry_id == ^entry_id,
        order_by: [desc: :revision],
        limit: 1

    case Brando.repo().all(query) do
      [] -> 0
      [revision] -> revision + 1
    end
  end
end

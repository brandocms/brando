defmodule Brando.Revisions do
  @moduledoc """

  **NOTE**: if you use revisions on a schema that has a relation you are
  preloading i.e:

      `mutation :update, {Project, preload: [:related_projects]}`

  You must pass `use_parent: true` to the field's dataloader to prevent
  dataloader loading the relation from the original entry, as opposed
  to leaving it from the revision:

      ```
      field :related_projects, list_of(:project),
          resolve: dataloader(MyApp.Projects, use_parent: true)
      ```
  """

  alias Brando.Revisions.Revision
  import Ecto.Query
  use Brando.Query

  query :list, Revision do
    fn query -> from(q in query) end
  end

  filters Revision do
    fn
      {:entry_id, entry_id}, query ->
        from q in query, where: q.entry_id == ^entry_id

      {:entry_type, entry_type}, query when is_binary(entry_type) ->
        entry_type = Module.concat([entry_type]) |> to_string()
        from q in query, where: q.entry_type == ^entry_type

      {:entry_type, entry_type}, query when is_atom(entry_type) ->
        entry_type = to_string(entry_type)
        from q in query, where: q.entry_type == ^entry_type

      {:revision, revision}, query ->
        from q in query, where: q.revision == ^revision

      {:active, active}, query ->
        from q in query, where: q.active == ^active
    end
  end

  def create_revision(%{__struct__: entry_type, id: entry_id} = entry, user, set_active \\ true) do
    user_id = if user == :system, do: nil, else: user.id
    entry_type_binary = to_string(entry_type)
    encoded_entry = encode_entry(entry)

    revision = %{
      active: set_active,
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
        if set_active do
          set_all_inactive_except(revision)
        end

        {:ok, revision}

      err ->
        err
    end
  end

  @doc """
  Create a revision based on `base_revision`.

  Merges in `entry_params` and stores as a new revision
  """
  def create_from_base_revision(entry_schema, base_revision_version, entry_id, entry_params, user) do
    {:ok, {_, {_, decoded_entry}}} = get_revision(entry_schema, entry_id, base_revision_version)
    updated_entry = Map.merge(decoded_entry, entry_params)
    create_revision(updated_entry, user, false)
  end

  def purge_revisions(entry_type, entry_id) do
    entry_type_binary = to_string(entry_type)

    query =
      from r in Revision,
        where:
          r.entry_type == ^entry_type_binary and
            r.entry_id == ^entry_id and
            r.active == false

    Brando.repo().delete_all(query)
  end

  def delete_revision(entry_type, entry_id, revision) do
    entry_type_binary = to_string(entry_type)

    query =
      from r in Revision,
        where:
          r.entry_type == ^entry_type_binary and
            r.entry_id == ^entry_id and
            r.revision == ^revision and
            r.active == false

    Brando.repo().delete_all(query)
  end

  @doc """
  Check if `schema` is revisioned
  """
  def is_revisioned(schema) do
    {:__revisioned__, 0} in schema.__info__(:functions)
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

  def get_active_revision(entry_type, entry_id) do
    entry_type_binary = to_string(entry_type)

    query =
      from r in Revision,
        where:
          r.entry_type == ^entry_type_binary and
            r.entry_id == ^entry_id and
            r.active == true,
        limit: 1

    case Brando.repo().all(query) do
      [] ->
        :error

      [revision] ->
        decoded_entry = decode_entry(revision.encoded_entry)
        {:ok, {revision, {revision.revision, decoded_entry}}}
    end
  end

  def set_revision(entry_schema, entry_id, revision_number) do
    {:ok, {revision, {_, new_entry}}} = get_revision(entry_schema, entry_id, revision_number)
    {:ok, {_, {_, base_entry}}} = get_active_revision(entry_schema, entry_id)
    do_set_revision(base_entry, new_entry, revision)
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
    |> Brando.Query.update()
    |> case do
      {:ok, new_entry} ->
        set_active(revision)
        set_all_inactive_except(revision)
        Brando.Datasource.update_datasource(entry_type, new_entry)
        {:ok, new_entry}

      err ->
        err
    end
  end

  def get_revision(%{__struct__: entry_type, id: entry_id}, revision_number) do
    get_revision(entry_type, entry_id, revision_number)
  end

  def get_revision(entry_type, entry_id, revision_number) do
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
end

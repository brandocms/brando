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

  @type changeset :: Ecto.Changeset.t()
  @type revision :: Brando.Revisions.Revision.t()
  @type revision_active :: boolean
  @type user :: Brando.Users.User

  use Brando.Query
  import Ecto.Query
  alias Brando.Datasource
  alias Brando.Query
  alias Brando.Revisions.Revision
  alias Brando.Utils

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

  @doc """
  Create a new revision from `entry` struct
  """
  @spec create_revision(map, user, revision_active) :: {:ok, revision} | {:error, changeset}
  def create_revision(%{__struct__: entry_type, id: entry_id} = entry, user, set_active \\ true) do
    user_id = if user == :system, do: nil, else: user.id
    entry_type_binary = to_string(entry_type)
    encoded_entry = Utils.term_to_binary(entry)

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
          deactivate_all_revisions_except(revision)
        end

        {:ok, revision}

      err ->
        err
    end
  end

  @doc """
  Set description for revision

  ## Example

      describe_revision(Project, entry.id, revision_number, "Different heading")

  """
  def describe_revision(entry_type, entry_id, revision_number, description) do
    entry_type_binary = to_string(entry_type)

    query =
      from r in Revision,
        where:
          r.entry_type == ^entry_type_binary and
            r.entry_id == ^entry_id and
            r.revision == ^revision_number,
        update: [set: [description: ^description]]

    Brando.repo().update_all(query, [])
  end

  @doc """
  Mark revision as protected

  ## Example

      protect_revision(Project, entry.id, revision_number, true)

  """
  def protect_revision(entry_type, entry_id, revision_number, protect) do
    entry_type_binary = to_string(entry_type)

    query =
      from r in Revision,
        where:
          r.entry_type == ^entry_type_binary and
            r.entry_id == ^entry_id and
            r.revision == ^revision_number,
        update: [set: [protected: ^protect]]

    Brando.repo().update_all(query, [])
  end

  @doc """
  Create a revision based on `base_revision`.

  Merges in `entry_params` and stores as a new revision
  """
  def create_from_base_revision(entry_schema, base_revision_version, entry_id, entry_params, user) do
    {:ok, {_, {_, decoded_entry}}} = get_revision(entry_schema, entry_id, base_revision_version)

    decoded_entry
    |> Map.merge(entry_params)
    |> create_revision(user, false)
  end

  @doc """
  Purge all revisions older than 14 days, which are not protected or active
  """
  def purge_revisions do
    query =
      from r in Revision,
        where:
          fragment("? < current_timestamp - interval '14 day'", r.inserted_at) and
            r.protected == false and
            r.active == false

    Brando.repo().delete_all(query)
  end

  @doc """
  Purge all inactive and unprotected revisions for `entry_type` and `entry_id`

  ## Example

      purge_revisions(Project, entry_id)

  """
  def purge_revisions(entry_type, entry_id) do
    entry_type_binary = to_string(entry_type)

    query =
      from r in Revision,
        where:
          r.entry_type == ^entry_type_binary and
            r.entry_id == ^entry_id and
            r.protected == false and
            r.active == false

    Brando.repo().delete_all(query)
  end

  @doc """
  Delete specific revision

  ## Example

      delete_revision(Project, entry_id, revision_number)

  """
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

  @doc """
  Get the last revision for `entry_type` and `entry_id`

  ## Example

      get_last_revision(Project, project.id)

  """
  def get_last_revision(entry_type, entry_id) do
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
        decoded_entry = Utils.binary_to_term(revision.encoded_entry)
        {:ok, {revision, {revision.revision, decoded_entry}}}
    end
  end

  @doc """
  Get active revision for `entry_type` and `entry_id`

  ## Example

      get_active_revision(Project, entry.id)

  """
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
        decoded_entry = Utils.binary_to_term(revision.encoded_entry)
        {:ok, {revision, {revision.revision, decoded_entry}}}
    end
  end

  @doc """
  Set entry to revision number.

  ## Example

      set_entry_to_revision(Project, project_id, wanted_revision_id)

  """
  def set_entry_to_revision(entry_schema, entry_id, revision_number) do
    {:ok, {revision, {_, new_entry}}} = get_revision(entry_schema, entry_id, revision_number)
    {:ok, {_, {_, base_entry}}} = get_active_revision(entry_schema, entry_id)
    do_set_entry_to_revision(base_entry, new_entry, revision)
  end

  defp do_set_entry_to_revision(
         %{__struct__: entry_type} = entry,
         decoded_entry,
         revision
       ) do
    entry
    |> entry_type.changeset(Map.delete(Map.from_struct(decoded_entry), :__meta__))
    |> Query.update()
    |> case do
      {:ok, new_entry} ->
        activate_revision(revision)
        deactivate_all_revisions_except(revision)
        Datasource.update_datasource(entry_type, new_entry)
        {:ok, new_entry}

      err ->
        err
    end
  end

  @doc """
  Get revision

  ## Example

      get_revision(Project, entry.id, revision_number)

  """
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
        decoded_entry = Utils.binary_to_term(revision.encoded_entry)
        {:ok, {revision, {revision.revision, decoded_entry}}}
    end
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

  defp activate_revision(revision) do
    query =
      from r in Revision,
        where:
          r.entry_type == ^revision.entry_type and
            r.entry_id == ^revision.entry_id and
            r.revision == ^revision.revision,
        update: [set: [active: true]]

    Brando.repo().update_all(query, [])
  end

  defp deactivate_all_revisions_except(revision) do
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
end

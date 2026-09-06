defmodule Brando.Authorization.Boundary do
  @moduledoc """
  Authorization at generated context boundaries and scoped admin reads.

  Public frontend queries keep their existing behavior outside an admin scope.
  Context mutations with a user always enforce groups once group mode is enabled.
  `:system` is reserved for explicitly trusted maintenance code.
  """
  alias Brando.Authorization.{Engine, Groups, Scope}
  alias Brando.Repo

  @scope_key {__MODULE__, :scope}
  @presentation_key {__MODULE__, :presentation}
  @query_action_key {__MODULE__, :query_action}

  def current_scope, do: Process.get(@scope_key)
  def put_scope(%Scope{} = scope), do: Process.put(@scope_key, scope)
  def put_scope(nil), do: Process.delete(@scope_key)

  @doc false
  def put_presentation(snapshot), do: Process.put(@presentation_key, snapshot)

  def presentation do
    case Process.get(@presentation_key) do
      %{scope: scope} = snapshot -> if scope == current_scope(), do: snapshot
      _ -> nil
    end
  end

  @doc "Runs scoped admin reads, restoring the previous process context afterwards."
  def with_scope(scope, fun) do
    previous = current_scope()
    put_scope(scope)

    try do
      fun.()
    after
      put_scope(previous)
    end
  end

  @doc false
  def run(:system, _action, _schema, fun), do: with_scope(nil, fn -> fun.(:system) end)

  def run(actor, action, schema, fun) do
    if Engine.enabled?() do
      scope = actor_scope(actor)

      result =
        Repo.transaction(fn ->
          if schema == Brando.Users.User, do: Groups.lock!()

          with_scope(scope, fn ->
            snapshot = Engine.snapshot(scope)

            allowed? =
              Engine.can?(snapshot, action, schema) or
                (schema == Brando.Users.User and action == :update and Engine.can?(snapshot, :update, :profile))

            unless allowed?, do: Repo.rollback(:forbidden)

            if scope.kind == :site and schema.__schema__(:prefix) != "public" and not is_binary(scope.prefix),
              do: Repo.rollback(:forbidden)

            result = Brando.Tenant.with_prefix(scope.prefix, fn -> fun.(snapshot.user) end)

            case result do
              {:error, reason} -> Repo.rollback(reason)
              value -> value
            end
          end)
        end)

      case result do
        {:ok, value} ->
          if schema == Brando.Users.User,
            do: Phoenix.PubSub.broadcast(Brando.pubsub(), "brando:authorization", {:authorization_changed, :all})

          value

        {:error, reason} ->
          {:error, reason}
      end
    else
      fun.(actor)
    end
  end

  def authorize(:system, _, _), do: :ok

  def authorize(actor, action, subject) do
    if Engine.enabled?(), do: Engine.authorize(actor_scope(actor), action, subject), else: :ok
  end

  def restore(actor, %{__struct__: schema} = entry) do
    run(actor, :restore, schema, fn user ->
      with :ok <- authorize(user, :restore, entry),
           changeset <- Ecto.Changeset.change(entry, deleted_at: nil),
           :ok <- change(user, :update, changeset),
           do: Repo.restore(entry)
    end)
  end

  def change(:system, _, _), do: :ok

  def change(actor, action, changeset) do
    if Engine.enabled?() do
      with :ok <- Engine.authorize_change(actor_scope(actor), action, changeset) do
        protect_account(changeset)
      end
    else
      :ok
    end
  end

  def query(query, schema) do
    if Engine.enabled?() and current_scope() do
      action =
        case Process.get(@query_action_key) do
          {action, ^schema} -> action
          _ -> :read
        end

      if schema == Brando.Content.Identifier,
        do: identifiers(query),
        else: Engine.scope_query(current_scope(), action, query, schema)
    else
      query
    end
  end

  def with_query_action(action, schema, fun) do
    previous = Process.get(@query_action_key)
    Process.put(@query_action_key, {action, schema})

    try do
      fun.()
    after
      if previous, do: Process.put(@query_action_key, previous), else: Process.delete(@query_action_key)
    end
  end

  @doc "Applies each source resource's read policy before identifier pagination."
  def identifiers(query) do
    if Engine.enabled?() and current_scope() do
      import Ecto.Query, only: [dynamic: 2, where: 3, from: 2, subquery: 1]
      snapshot = Engine.snapshot(current_scope())

      allowed =
        Brando.Authorization.Catalog.schemas()
        |> Enum.filter(&Engine.can?(snapshot, :read, &1))
        |> Enum.reduce(dynamic([identifier], false), fn schema, allowed ->
          ids = from(entry in Engine.scope(current_scope(), :read, schema), select: entry.id)
          dynamic([identifier], ^allowed or (identifier.schema == ^schema and identifier.entry_id in subquery(ids)))
        end)

      where(query, [identifier], ^allowed)
    else
      query
    end
  end

  def cache_options(args) do
    if Engine.enabled?() and current_scope(), do: Map.delete(args, :cache), else: args
  end

  @doc "Filters metadata queries through the parent resource's read policy."
  def subject_query(query, schema, id, action \\ :read) do
    if Engine.enabled?() and current_scope() do
      import Ecto.Query, only: [from: 2]
      schema = Brando.Authorization.Catalog.schema(schema)

      visible =
        schema && Repo.one(from(e in Engine.scope(current_scope(), action, schema), where: e.id == ^id, select: e.id))

      query = Ecto.Query.put_query_prefix(query, current_scope().prefix || "public")
      if visible, do: query, else: from(q in query, where: false)
    else
      query
    end
  end

  @doc "Checks a concrete record before a custom context operation."
  def authorize_record(:system, _, _, _), do: :ok

  def authorize_record(actor, action, schema, id) do
    if Engine.enabled?() do
      import Ecto.Query, only: [from: 2]
      scope = actor_scope(actor)

      with schema when not is_nil(schema) <- Brando.Authorization.Catalog.schema(schema),
           record when not is_nil(record) <- Repo.one(from(e in Engine.scope(scope, action, schema), where: e.id == ^id)),
           :ok <- Engine.authorize(scope, action, record),
           do: :ok,
           else: (_ -> {:error, :forbidden})
    else
      :ok
    end
  end

  @doc false
  def admin_record(action, schema, id) do
    if current_scope(), do: authorize_record(current_scope(), action, schema, id), else: :ok
  end

  def actor_scope(%Scope{} = scope), do: scope

  def actor_scope(%{id: id} = actor) do
    case current_scope() do
      %Scope{user_id: ^id} = scope -> scope
      _ -> Scope.current(actor)
    end
  end

  def actor_scope(actor), do: Scope.current(actor)

  defp protect_account(%{data: %{__struct__: Brando.Users.User, id: id}, changes: changes}) when not is_nil(id) do
    if Map.get(changes, :active) == false or Map.get(changes, :deleted_at), do: Groups.protect_account!(id)
    :ok
  end

  defp protect_account(_), do: :ok
end

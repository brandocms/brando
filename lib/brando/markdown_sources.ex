defmodule Brando.MarkdownSources do
  @moduledoc "Repository Markdown, immutable local versions, and explicit block placements."
  import Ecto.Query, only: [from: 2]
  alias Brando.MarkdownSources.{Connection, Event, Source, Version}
  alias Brando.Repo

  def authorize(:system, _), do: :ok
  def authorize(id, action) when is_integer(id), do: authorize(%{id: id}, action)

  def authorize(actor, action) do
    if Brando.Authorization.Engine.enabled?() do
      Brando.Authorization.Engine.authorize(Brando.Authorization.Scope.current(actor), action, :markdown_sources)
    else
      id = if is_map(actor), do: Map.get(actor, :id)
      user = id && Repo.get(Brando.Users.User, id)
      roles = if action in [:read, :publish], do: [:editor, :admin, :superuser], else: [:admin, :superuser]

      role =
        if user && Brando.Tenant.enabled?() do
          scope = Brando.Authorization.Scope.current(user)
          site = scope.site_id && Brando.Tenant.Registry.get_site(scope.site_id)
          if site, do: Brando.Tenant.Access.role_for(user, site)
        else
          user && user.role
        end

      if user && user.active && is_nil(user.deleted_at) && role in roles, do: :ok, else: {:error, :forbidden}
    end
  end

  def list_sources do
    Repo.all(from(s in Source, order_by: [asc: s.name, asc: s.id]))
  end

  def get_source(id), do: if(integer_id(id), do: Repo.get(Source, integer_id(id)))
  def versions(source_id), do: Repo.all(from(v in Version, where: v.source_id == ^source_id, order_by: [desc: v.id]))

  def events(source_id),
    do: Repo.all(from(e in Event, where: e.source_id == ^source_id, order_by: [desc: e.id], limit: 20))

  def get_version(source_id, version_id) do
    with source_id when not is_nil(source_id) <- integer_id(source_id),
         version_id when not is_nil(version_id) <- integer_id(version_id) do
      Repo.one(from(v in Version, where: v.id == ^version_id and v.source_id == ^source_id))
    end
  end

  def save_source(source, attrs, actor) do
    with :ok <- authorize(actor, if(source.id, do: :update, else: :create)) do
      changeset = Source.changeset(source, attrs)
      key = Ecto.Changeset.get_field(changeset, :connection)

      changeset =
        if not Ecto.Changeset.get_field(changeset, :enabled) or match?({:ok, _}, Connection.current(key)),
          do: changeset,
          else: Ecto.Changeset.add_error(changeset, :connection, "is not enabled for this environment")

      # Changing a document identity would also reinterpret old pins. Require a
      # new source once imported; names and enabled state can still be edited.
      changeset =
        if source.latest_version_id && Enum.any?([:connection, :ref, :path], &Ecto.Changeset.changed?(changeset, &1)),
          do: Ecto.Changeset.add_error(changeset, :path, "create a new source to change an imported document's identity"),
          else: changeset

      Brando.MarkdownSources.Publication.with_source_lock(source.id || "new", fn ->
        Repo.transaction(fn ->
          result = if source.id, do: Repo.update(changeset), else: Repo.insert(changeset)

          case result do
            {:ok, source} ->
              audit(source, "source.saved", actor)
              source

            {:error, reason} ->
              Repo.rollback(reason)
          end
        end)
      end)
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale_source}
  end

  def refresh(source_id, actor) do
    with :ok <- authorize(actor, :sync),
         %Source{enabled: true} = source <- get_source(source_id),
         {:ok, connection} <- Connection.current(source.connection) do
      args = %{source_id: source.id, connection: source.connection, generation: Connection.generation(connection)}

      Repo.transaction(fn ->
        audit(source, "source.refresh_requested", actor)

        case args |> Brando.Tenant.Job.attach() |> Brando.Worker.MarkdownSourceSync.new() |> Oban.insert() do
          {:ok, job} -> job
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :source_unavailable}
    end
  end

  def render(data) do
    case resolved_version(data) do
      %Version{html: html} -> html
      _ -> ""
    end
  end

  def resolved_version(%{source_id: source_id, policy: policy, version_id: version_id}) do
    with %Source{} = source <- get_source(source_id) do
      get_version(source.id, if(policy == :follow, do: source.latest_version_id, else: version_id))
    end
  end

  def resolved_version(_), do: nil

  # Discrete ref commits can complete a previously invalid review selection.
  # Clear only this validator's old error before the op store preserves invalid
  # raw params; otherwise it would replay the earlier empty version on save.
  def revalidate_placement(changeset, actor) do
    case Ecto.Changeset.get_field(changeset, :data) do
      %Ecto.Changeset{data: %Brando.Villain.Blocks.MarkdownSourceBlock{}} = data ->
        errors = Enum.reject(changeset.errors, fn {_, {_, opts}} -> opts[:validation] == :markdown_source end)
        changeset = %{changeset | errors: errors, valid?: errors == [] and data.valid?}
        changeset |> Ecto.Changeset.force_change(:data, Ecto.Changeset.apply_changes(data)) |> validate_placement(actor)

      _ ->
        changeset
    end
  end

  def validate_placement(changeset, actor) do
    case Ecto.Changeset.get_field(changeset, :data) do
      %Brando.Villain.Blocks.MarkdownSourceBlock{data: data} ->
        old =
          case changeset.data.data do
            %Brando.Villain.Blocks.MarkdownSourceBlock{data: old} -> old
            _ -> nil
          end

        validate_placement_data(changeset, data, old, actor)

      _ ->
        changeset
    end
  end

  defp validate_placement_data(changeset, data, old, actor) do
    fields = [:source_id, :version_id, :policy]
    changed? = is_nil(old) or Map.take(data, fields) != Map.take(old, fields)

    cond do
      not changed? ->
        changeset

      is_nil(data.source_id) and (is_nil(old) or is_nil(old.source_id)) ->
        changeset

      authorize(actor, :publish) != :ok ->
        Ecto.Changeset.add_error(changeset, :data, "You cannot publish Markdown source updates",
          validation: :markdown_source
        )

      is_nil(data.source_id) ->
        changeset

      true ->
        with %Source{} = source <- get_source(data.source_id),
             {:ok, _} <- Connection.current(source.connection),
             true <- is_nil(data.version_id) or not is_nil(get_version(source.id, data.version_id)),
             true <- data.policy == :follow or not is_nil(data.version_id) do
          changeset
        else
          _ ->
            Ecto.Changeset.add_error(
              changeset,
              :data,
              "Choose an available source and an exact version for review or pinning",
              validation: :markdown_source
            )
        end
    end
  end

  def consumer_entries(source_id, policies \\ ["follow"]) do
    # Discover persisted placements explicitly, including nested blocks. Walking
    # roots and rendering fragments uses the existing content dependency pipeline.
    Repo.all(
      from(r in Brando.Content.Ref,
        where: not is_nil(r.block_id) and r.active == true,
        where: fragment("?->>'type' = 'markdown_source'", r.data),
        where: fragment("?->'data'->>'source_id' = ?", r.data, ^to_string(source_id)),
        where: fragment("?->'data'->>'policy'", r.data) in ^policies,
        select: r.block_id,
        distinct: true
      )
    )
    |> Brando.Content.BlockReferences.reject_blocks_belonging_to_entry(nil)
  end

  def audit(source, action, actor \\ :system, attrs \\ %{}) do
    actor_id = if is_map(actor), do: Map.get(actor, :id), else: integer_id(actor)
    Repo.insert!(struct(Event, Map.merge(%{source_id: source.id, action: action, actor_id: actor_id}, attrs)))
  end

  def integer_id(value) when is_integer(value) and value > 0, do: value

  def integer_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  def integer_id(_), do: nil

  def broadcast(source) do
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic(), {:markdown_source_updated, source.id})
    :ok
  end

  def topic, do: "markdown-sources:#{Brando.Tenant.current_prefix() || "public"}"
end

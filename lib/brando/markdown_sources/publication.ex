defmodule Brando.MarkdownSources.Publication do
  @moduledoc false
  alias Brando.MarkdownSources.{Connection, Source}
  import Ecto.Query, only: [from: 2]
  alias Brando.Repo

  def entry_saved(%{__struct__: schema, id: id}, actor) do
    if function_exported?(schema, :__blocks_fields__, 0) and schema.__blocks_fields__() != [] do
      Enum.each(Brando.MarkdownSources.list_sources(), fn source ->
        if id in Map.get(Brando.MarkdownSources.consumer_entries(source.id, ["follow", "review", "pinned"]), schema, []) do
          Brando.MarkdownSources.audit(source, "placement.saved", actor, %{message: "#{inspect(schema)} ##{id}"})

          with {:ok,
                %{auto_deploy: true, destination: %{site: %{delivery_mode: :static}, environment: %{live: true}}} =
                  connection} <- Connection.current(source.connection),
               true <- source.enabled and not is_nil(source.latest_version_id) do
            args = %{
              source_id: source.id,
              version_id: source.latest_version_id,
              source_revision: source.publication_sequence,
              connection: source.connection,
              generation: Connection.generation(connection),
              entry_schema: Atom.to_string(schema),
              entry_id: id,
              entry_revision: persisted_entry_revision(schema, id)
            }

            case args |> Brando.Tenant.Job.attach() |> Brando.Worker.MarkdownSourcePublish.new() |> Oban.insert() do
              {:ok, _} ->
                :ok

              _ ->
                Brando.MarkdownSources.audit(source, "publication.failed", actor, %{
                  message: "Could not queue publication; use Publishing to request a build"
                })
            end
          else
            _ -> :ok
          end
        end
      end)
    end

    :ok
  end

  def render_consumers!(entries) do
    Enum.reduce(entries, MapSet.new(), fn {schema, ids}, visited ->
      Enum.reduce(ids, visited, &render_entry!({schema, &1}, &2))
    end)
  end

  defp render_entry!({schema, id} = key, visited) do
    if MapSet.member?(visited, key) do
      visited
    else
      visited = MapSet.put(visited, key)

      case Brando.Content.Blocks.render_entry(schema, id) do
        {:ok, %Brando.Pages.Fragment{}} ->
          Brando.Content.Blocks.list_block_ids_using_fragment(id)
          |> Brando.Content.BlockReferences.reject_blocks_belonging_to_entry(nil)
          |> Enum.reduce(visited, fn {parent_schema, ids}, acc ->
            Enum.reduce(ids, acc, &render_entry!({parent_schema, &1}, &2))
          end)

        {:ok, _} ->
          visited

        _ ->
          Repo.rollback(:render_failed)
      end
    end
  end

  def enqueue(source, %{destination: %{site: %{delivery_mode: :static}, environment: %{live: true}}} = connection) do
    if Map.get(connection, :auto_deploy, false) and map_size(Brando.MarkdownSources.consumer_entries(source.id)) > 0 do
      args = %{
        source_id: source.id,
        version_id: source.latest_version_id,
        source_revision: source.publication_sequence,
        connection: source.connection,
        generation: Connection.generation(connection)
      }

      args |> Brando.Tenant.Job.attach() |> Brando.Worker.MarkdownSourcePublish.new() |> Oban.insert()
    else
      {:ok, :rendered}
    end
  end

  def enqueue(_, _), do: {:ok, :rendered}

  def publish(args), do: with_source_lock(args["source_id"], fn -> do_publish(args) end)

  defp do_publish(args) do
    with %Source{} = source <- Brando.MarkdownSources.get_source(args["source_id"]),
         true <-
           source.enabled and source.publication_sequence == args["source_revision"] and
             same_content?(source, args["version_id"]),
         {:ok, connection} <- Connection.current(source.connection),
         true <- connection.key == args["connection"] and Connection.generation(connection) == args["generation"],
         true <- Map.get(connection, :auto_deploy, false),
         true <- entry_current?(args),
         %{site: %{delivery_mode: :static} = site, environment: %{live: true} = environment} <- connection.destination,
         publisher when not is_nil(publisher) <- publisher(connection),
         :ok <- Brando.MarkdownSources.authorize(publisher, :publish),
         :ok <- ensure_rendered(source),
         args <- refresh_entry_revision(args),
         args <- Map.put(args, "placements", placement_fingerprint(source.id)),
         {:ok, _build} <- request_build_once(source, site, environment, publisher, args) do
      Brando.MarkdownSources.broadcast(source)
    else
      {:error, reason} when reason in [:connection_disabled, :destination_forbidden, :forbidden] ->
        {:cancel, :publication_superseded}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:cancel, :publication_superseded}
    end
  end

  defp request_build_once(source, site, environment, publisher, args) do
    Repo.transaction(fn ->
      existing = source.build_id && Brando.SSG.Builds.get_build(source.build_id)

      if existing && existing.markdown_context == args do
        existing
      else
        case Brando.SSG.Builds.request_build(site, environment,
               creator: publisher,
               creator_id: publisher.id,
               auto_deploy: true,
               note: "Markdown source: #{source.name}",
               markdown_context: args
             ) do
          {:ok, build} ->
            source |> Ecto.Changeset.change(build_id: build.id, publication_status: "Build queued") |> Repo.update!()
            Brando.MarkdownSources.audit(source, "publication.queued", publisher, %{version_id: source.latest_version_id})
            build

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end
    end)
  end

  # Called under the existing per-site deploy lock immediately before external
  # effects. Automatic artifacts lose eligibility when their source/config changes.
  def current?(%{markdown_context: context}) when map_size(context) == 0, do: true

  def current?(%{markdown_context: context, site_id: site_id, environment_id: environment_id}) do
    Brando.Tenant.Job.run(context, fn ->
      with %Source{enabled: true} = source <- Brando.MarkdownSources.get_source(context["source_id"]),
           true <-
             source.publication_sequence == context["source_revision"] and same_content?(source, context["version_id"]),
           true <- placement_fingerprint(source.id) == context["placements"],
           {:ok, connection} <- Connection.current(source.connection),
           true <- Connection.generation(connection) == context["generation"],
           %{site: %{id: ^site_id}, environment: %{id: ^environment_id, live: true}} <- connection.destination,
           true <- Map.get(connection, :auto_deploy, false),
           publisher when not is_nil(publisher) <- publisher(connection),
           :ok <- Brando.MarkdownSources.authorize(publisher, :publish),
           :ok <- Brando.Authorization.Operations.authorize(publisher, :deploy, :publishing, site_id) do
        entry_current?(context)
      else
        _ -> false
      end
    end) == true
  end

  def current?(_), do: false

  defp ensure_rendered(source) do
    case Repo.transaction(fn ->
           source.id |> Brando.MarkdownSources.consumer_entries(["follow", "review", "pinned"]) |> render_consumers!()
         end) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :render_failed}
    end
  end

  defp entry_current?(%{"entry_schema" => schema, "entry_id" => id, "entry_revision" => revision}) do
    schema = String.to_existing_atom(schema)

    case Brando.Blueprint.EntryQuery.get(schema, id) do
      {:ok, entry} -> entry_revision(entry) == revision
      _ -> false
    end
  rescue
    _ -> false
  end

  defp entry_current?(_), do: true

  def with_source_lock(id, fun) do
    Brando.Tenant.Lock.with("markdown-source:#{Brando.Tenant.current_prefix()}:#{id}", fun)
  end

  def guard_deploy(%{markdown_context: context} = build, fun) when map_size(context) > 0 do
    Brando.Tenant.Job.run(context, fn ->
      with_source_lock(context["source_id"], fn ->
        newest =
          Repo.one(from(b in Brando.SSG.Build, where: b.site_id == ^build.site_id, select: max(b.build_number)),
            prefix: "public"
          )

        if newest == build.build_number and current?(build), do: fun.(), else: {:error, :markdown_publication_superseded}
      end)
    end)
  end

  def guard_deploy(_, fun), do: fun.()

  defp same_content?(source, version_id) do
    old = Brando.MarkdownSources.get_version(source.id, version_id)
    latest = Brando.MarkdownSources.get_version(source.id, source.latest_version_id)
    old && latest && old.content_hash == latest.content_hash
  end

  def placement_fingerprint(source_id) do
    refs =
      Repo.all(
        from(r in Brando.Content.Ref,
          where: not is_nil(r.block_id),
          where: fragment("?->>'type' = 'markdown_source'", r.data),
          where: fragment("?->'data'->>'source_id' = ?", r.data, ^to_string(source_id)),
          order_by: r.id,
          select: {r.id, r.block_id, r.active, r.data}
        )
      )

    entries =
      source_id
      |> Brando.MarkdownSources.consumer_entries(["follow", "review", "pinned"])
      |> Enum.flat_map(fn {schema, ids} ->
        Enum.map(ids, fn id ->
          case Brando.Blueprint.EntryQuery.get(schema, id) do
            {:ok, entry} -> {schema, id, entry_revision(entry)}
            _ -> {schema, id, nil}
          end
        end)
      end)
      |> Enum.sort()

    digest({refs, entries})
  end

  defp refresh_entry_revision(%{"entry_schema" => schema, "entry_id" => id} = args),
    do: Map.put(args, "entry_revision", persisted_entry_revision(String.to_existing_atom(schema), id))

  defp refresh_entry_revision(args), do: args

  defp persisted_entry_revision(schema, id) do
    case Brando.Blueprint.EntryQuery.get(schema, id) do
      {:ok, entry} -> entry_revision(entry)
      _ -> nil
    end
  end

  defp entry_revision(%{__struct__: schema} = entry) do
    render_fields =
      Enum.map(schema.__blocks_fields__(), fn field -> String.to_existing_atom("rendered_#{field.name}") end)

    entry |> Map.take([:updated_at, :status, :deleted_at] ++ render_fields) |> digest()
  end

  defp digest(term),
    do: term |> :erlang.term_to_binary() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

  defp publisher(connection) do
    case Map.get(connection, :publisher_id) do
      id when is_integer(id) -> Repo.get(Brando.Users.User, id)
      _ -> nil
    end
  end
end

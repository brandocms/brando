defmodule BrandoAdmin.Dashboard do
  @moduledoc "Read-only dashboard data, scoped to the current actor and tenant."
  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Boundary, Scope}
  alias Brando.Blueprint.Identifier.Generator
  alias Brando.Content.Identifier
  alias Brando.Images.{ConfigResolver, Image, Size}
  alias Brando.Images.Operations.Sizing
  alias Brando.Repo
  alias Brando.Utils

  def load(user) do
    scope = Boundary.actor_scope(user)

    Boundary.with_scope(scope, fn ->
      Brando.Tenant.with_prefix(scope.prefix || Brando.Tenant.current_prefix(), fn ->
        %{
          recent: entries(user, :recent, 6),
          drafts: entries(user, :drafts, 4),
          scheduled: scheduled(user),
          expiring: expiring(user)
        }
      end)
    end)
  end

  defp entries(user, kind, limit) do
    schemas =
      Brando.Content.Identifier.Registry.list_persistent_identifier_modules(:include_brando)
      |> Enum.filter(&function_exported?(&1, :__admin_route__, 2))

    query = from i in Identifier, where: i.schema in ^schemas, order_by: [desc: i.updated_at, desc: i.id]
    query = if kind == :drafts, do: from(i in query, where: i.status == :draft), else: query
    query = Boundary.identifiers(query)

    # Legacy rules may contain record predicates. Walk batches until enough visible
    # records are found; do not expose identifier snapshots before checking the source.
    Stream.unfold(0, fn offset ->
      case Repo.all(from(i in query, limit: 32, offset: ^offset)) do
        [] -> nil
        batch -> {batch, offset + length(batch)}
      end
    end)
    |> Stream.flat_map(& &1)
    |> Stream.map(fn identifier ->
      with entry when not is_nil(entry) <- Repo.get(identifier.schema, identifier.entry_id),
           true <- is_nil(Map.get(entry, :deleted_at)),
           true <- allowed?(user, :read, entry),
           true <- kind != :drafts or allowed?(user, :update, entry) do
        %{
          title: identifier.title,
          type: Brando.Blueprint.get_singular(identifier.schema) |> Brando.Utils.humanize(),
          icon: Brando.Blueprint.get_icon(identifier.schema),
          cover: cover(kind, identifier, entry),
          language: identifier.language,
          status: identifier.status,
          updated_at: identifier.updated_at,
          editor_id: Map.get(entry, :updated_by_id) || Map.get(entry, :creator_id),
          path: if(allowed?(user, :update, entry), do: identifier.schema.__admin_route__(:update, [entry.id]))
        }
      else
        _ -> nil
      end
    end)
    |> Stream.reject(&is_nil/1)
    |> Enum.take(limit)
    |> put_editors()
  end

  # A card's cover in every size the image has, so the browser can take one
  # that is sharp at the card's width. The identifier's own cover is only a
  # thumbnail; it stands in when the image has no sizes yet.
  defp cover(:recent, identifier, entry) do
    case Generator.cover_image(identifier.schema, entry) do
      %Image{sizes: sizes} = image when is_map(sizes) and map_size(sizes) > 0 -> sized_cover(image)
      _ -> thumb_cover(identifier)
    end
  end

  defp cover(_kind, identifier, _entry), do: thumb_cover(identifier)

  defp thumb_cover(%{cover: nil}), do: nil
  defp thumb_cover(%{cover: url}), do: %{src: url, srcset: nil}

  defp sized_cover(image) do
    {:ok, config} = ConfigResolver.get(image)

    # Low-quality sizes are blur placeholders, not candidates
    candidates =
      for {key, %{"size" => geometry} = size_config} <- config.sizes,
          Map.has_key?(image.sizes, key),
          Map.get(size_config, "quality", 100) >= 30,
          {:ok, dimensions} <- [Size.dimensions(geometry)],
          width = rendered_width(image, dimensions, size_config) do
        {width, Utils.img_url(image, key, prefix: Utils.media_url())}
      end
      |> Enum.sort()
      |> Enum.uniq_by(&elem(&1, 0))

    case candidates do
      [] ->
        %{src: Utils.img_url(image, :thumb, prefix: Utils.media_url()), srcset: nil}

      _ ->
        {_width, src} = Enum.find(candidates, &(elem(&1, 0) >= 600)) || Enum.max(candidates)
        %{src: src, srcset: Enum.map_join(candidates, ", ", fn {width, url} -> "#{url} #{width}w" end)}
    end
  end

  # The width a size is actually saved at, which `srcset` needs.
  defp rendered_width(%{width: width, height: height}, _box, size_config)
       when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    size_config |> Sizing.processed_dimensions({width, height}) |> elem(0)
  end

  defp rendered_width(_image, {box_width, _box_height}, _size_config), do: box_width

  # Who last edited each entry (its creator until someone edits it), loaded
  # in one query for the whole list.
  defp put_editors(entries) do
    ids = entries |> Enum.map(& &1.editor_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    users =
      if ids == [],
        do: %{},
        else: Map.new(Repo.all(from(u in Brando.Users.User, where: u.id in ^ids, preload: :avatar)), &{&1.id, &1})

    Enum.map(entries, &Map.put(&1, :editor, Map.get(users, &1.editor_id)))
  end

  # The next publications, filtered in the query (expiries have their own
  # panel), each entry checked until four are found
  defp scheduled(user) do
    [kinds: [:publish, :revision]]
    |> Brando.Publisher.waiting_jobs()
    |> Stream.flat_map(fn job ->
      with schema when not is_nil(schema) <- Brando.Authorization.Catalog.schema(job.args["schema"]),
           true <- function_exported?(schema, :__admin_route__, 2),
           entry when not is_nil(entry) <- Repo.get(schema, job.args["id"]),
           true <- is_nil(Map.get(entry, :deleted_at)),
           true <- allowed?(user, :read, entry) and allowed?(user, :update, entry),
           %Identifier{} = identifier <- Brando.Content.Identifier.Queries.identifier_for(entry) do
        [
          %{
            title: identifier.title,
            type: Brando.Blueprint.get_singular(schema) |> Brando.Utils.humanize(),
            icon: Brando.Blueprint.get_icon(schema),
            path: schema.__admin_route__(:update, [entry.id]),
            scheduled_at: job.scheduled_at
          }
        ]
      else
        _ -> []
      end
    end)
    |> Enum.take(4)
  end

  @expiring_days 14

  # Published entries that expire in the next two weeks, soonest first, that
  # the user may edit.
  defp expiring(user) do
    now = DateTime.utc_now()

    user
    |> BrandoAdmin.Schedule.items(now, DateTime.add(now, @expiring_days, :day), kinds: [:expire])
    |> Enum.filter(& &1.path)
    |> Enum.take(4)
  end

  defp allowed?(user, action, entry) do
    if Brando.Authorization.enabled?() do
      Brando.Authorization.can?(Boundary.current_scope() || Scope.current(user), action, entry)
    else
      Module.concat(Brando.authorization(), Can).can?(user, action, entry) == {:ok, :authorized}
    end
  end
end

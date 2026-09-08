defmodule BrandoAdmin.Dashboard do
  @moduledoc "Read-only dashboard data, scoped to the current actor and tenant."
  import Ecto.Query, only: [from: 2]
  use Gettext, backend: Brando.Gettext

  alias Brando.Authorization.{Boundary, Scope}
  alias Brando.Content.Identifier
  alias Brando.Repo

  def load(user) do
    scope = Boundary.actor_scope(user)

    Boundary.with_scope(scope, fn ->
      Brando.Tenant.with_prefix(scope.prefix || Brando.Tenant.current_prefix(), fn ->
        %{
          recent: entries(user, :recent, 8),
          drafts: entries(user, :drafts, 4),
          scheduled: scheduled(user),
          shortcuts: shortcuts(user)
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
          language: identifier.language,
          status: identifier.status,
          updated_at: identifier.updated_at,
          path: if(allowed?(user, :update, entry), do: identifier.schema.__admin_route__(:update, [entry.id]))
        }
      else
        _ -> nil
      end
    end)
    |> Stream.reject(&is_nil/1)
    |> Enum.take(limit)
  end

  defp scheduled(user) do
    {:ok, jobs} = Brando.Publisher.list_jobs()

    jobs
    |> Enum.filter(&(&1.state in ["scheduled", "available", "retryable", "executing"]))
    |> Enum.flat_map(fn job ->
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

  defp shortcuts(user) do
    [
      %{
        label: gettext("Pages"),
        path: "/admin/pages",
        icon: "hero-document-text",
        action: :read,
        schema: Brando.Pages.Page
      },
      %{
        label: gettext("Images"),
        path: "/admin/assets/images",
        icon: "hero-photo",
        action: :read,
        schema: Brando.Images.Image
      },
      %{
        label: gettext("Navigation"),
        path: "/admin/config/navigation/menus",
        icon: "hero-bars-3",
        action: :read,
        schema: Brando.Navigation.Menu
      },
      %{
        label: gettext("Globals"),
        path: "/admin/globals",
        icon: "hero-adjustments-horizontal",
        action: :update,
        schema: Brando.Sites.GlobalSet
      }
    ]
    |> Enum.filter(&allowed?(user, &1.action, struct(&1.schema)))
  end

  defp allowed?(user, action, entry) do
    if Brando.Authorization.enabled?() do
      Brando.Authorization.can?(Boundary.current_scope() || Scope.current(user), action, entry)
    else
      Module.concat(Brando.authorization(), Can).can?(user, action, entry) == {:ok, :authorized}
    end
  end
end

defmodule Brando.ListingViews do
  @moduledoc """
  Saved listing views: an admin listing's filters, status, sort and page size
  under a name, so an editor can get back to them.

  A view is personal, or shared with everyone who can open the listing (read
  access to its schema). Everyone renames, updates and deletes their own
  views; someone else's shared view only those who may manage shared views:
  the `brando.listing_views.manage` permission with group authorization, the
  admin or superuser role without. Each person can also pick one view, theirs
  or a shared one, to open a listing with (`default_view/3`).

  Views live in each site environment, like the content their filters select
  (the `brando_215` migration). A listing is named by its schema and listing
  name; applying a view navigates to the listing's URL with the view's
  parameters, checked again with `Brando.ListingViews.Params.sanitize/3` so a
  filter the listing no longer has is dropped.
  """

  import Ecto.Query

  alias Brando.Authorization.Boundary
  alias Brando.Authorization.Engine
  alias Brando.ListingViews.Default
  alias Brando.ListingViews.View
  alias Brando.Repo
  alias Brando.Users.User

  @type listing :: atom() | String.t()

  @doc "The views `user` sees on `listing` of `schema`: their own and the shared ones, by name."
  @spec list_views(User.t(), module(), listing()) :: [View.t()]
  def list_views(%User{} = user, schema, listing) do
    if can_see?(user, schema) do
      schema
      |> visible(listing, user)
      |> order_by([v], asc: fragment("lower(?)", v.name), asc: v.id)
      |> preload(:creator)
      |> Repo.all(savepoint())
    else
      []
    end
  rescue
    error in Postgrex.Error -> missing_table(error, __STACKTRACE__, [])
  end

  @doc "A view `user` sees on `listing` of `schema`, by id."
  @spec get_view(User.t(), module(), listing(), term()) :: {:ok, View.t()} | {:error, :not_found}
  def get_view(%User{} = user, schema, listing, id) do
    with {id, ""} <- Integer.parse(to_string(id)),
         true <- can_see?(user, schema),
         %View{} = view <- schema |> visible(listing, user) |> where([v], v.id == ^id) |> preload(:creator) |> Repo.one() do
      {:ok, view}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Saves a view of `listing` of `schema` for `user`: `name`, `params` (see
  `Brando.ListingViews.Params`) and `shared`. `{:error, :unavailable}` in an
  environment that has not run the brando_215 migration.
  """
  @spec create_view(User.t(), module(), listing(), map()) ::
          {:ok, View.t()} | {:error, :forbidden | :unavailable | Ecto.Changeset.t()}
  def create_view(%User{} = user, schema, listing, attrs) do
    if can_see?(user, schema) do
      %View{creator_id: user.id, schema: schema_name(schema), listing: to_string(listing)}
      |> View.changeset(attrs)
      |> Repo.insert(savepoint())
      |> preload_creator()
    else
      {:error, :forbidden}
    end
  rescue
    error in Postgrex.Error -> missing_table(error, __STACKTRACE__, {:error, :unavailable})
  end

  @doc "Changes a view's name, parameters or sharing, when `user` may (`can_manage?/2`)."
  @spec update_view(User.t(), View.t(), map()) :: {:ok, View.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  def update_view(%User{} = user, %View{} = view, attrs) do
    if can_manage?(user, view) do
      view
      |> View.changeset(attrs)
      |> Repo.update()
      |> preload_creator()
    else
      {:error, :forbidden}
    end
  end

  @doc "Deletes a view, when `user` may (`can_manage?/2`). It stops being anyone's default."
  @spec delete_view(User.t(), View.t()) :: {:ok, View.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  def delete_view(%User{} = user, %View{} = view) do
    if can_manage?(user, view), do: Repo.delete(view), else: {:error, :forbidden}
  end

  @doc """
  Whether `user` may rename, update and delete `view`: their own, or a shared
  one when they may manage shared views (`moderator?/1`).
  """
  @spec can_manage?(User.t(), View.t()) :: boolean()
  def can_manage?(%User{id: id}, %View{creator_id: id}), do: true
  def can_manage?(%User{} = user, %View{shared: true}), do: moderator?(user)
  def can_manage?(_user, _view), do: false

  @doc """
  Whether `user` may manage the views other people share: the
  `brando.listing_views.manage` permission with group authorization, the
  admin or superuser role without.
  """
  @spec moderator?(User.t()) :: boolean()
  def moderator?(%User{} = user) do
    if Engine.enabled?(),
      do: Boundary.authorize(user, :manage, :listing_views) == :ok,
      else: user.role in [:admin, :superuser]
  end

  @doc "The view `user` opens `listing` of `schema` with, if they picked one they still see."
  @spec default_view(User.t(), module(), listing()) :: View.t() | nil
  def default_view(%User{} = user, schema, listing) do
    if can_see?(user, schema) do
      schema
      |> visible(listing, user)
      |> join(:inner, [v], d in Default, on: d.view_id == v.id and d.user_id == ^user.id)
      |> Repo.one(savepoint())
    end
  rescue
    error in Postgrex.Error -> missing_table(error, __STACKTRACE__, nil)
  end

  @doc "Makes `view` the one `user` opens its listing with, in place of any other."
  @spec set_default(User.t(), View.t()) :: {:ok, Default.t()} | {:error, :forbidden}
  def set_default(%User{} = user, %View{} = view) do
    if visible?(user, view) and can_see?(user, view.schema) do
      Repo.insert(
        %Default{user_id: user.id, view_id: view.id, schema: view.schema, listing: view.listing},
        on_conflict: {:replace, [:view_id, :updated_at]},
        conflict_target: [:user_id, :schema, :listing]
      )
    else
      {:error, :forbidden}
    end
  end

  @doc "Opens `listing` of `schema` without a view for `user` again."
  @spec clear_default(User.t(), module(), listing()) :: :ok
  def clear_default(%User{} = user, schema, listing) do
    Default
    |> where([d], d.user_id == ^user.id and d.schema == ^schema_name(schema) and d.listing == ^to_string(listing))
    |> Repo.delete_all()

    :ok
  end

  @doc ~S(The name views are stored under for `schema`: `"Elixir.MyApp.Projects.Project"`.)
  @spec schema_name(module() | String.t()) :: String.t()
  def schema_name(schema) when is_binary(schema), do: schema
  def schema_name(schema) when is_atom(schema), do: Atom.to_string(schema)

  defp visible(schema, listing, user) do
    from(v in View,
      where: v.schema == ^schema_name(schema) and v.listing == ^to_string(listing),
      where: v.shared == true or v.creator_id == ^user.id
    )
  end

  defp visible?(%User{id: id}, %View{creator_id: id}), do: true
  defp visible?(_user, %View{shared: shared}), do: shared

  # Shared means everyone who can open the listing, so a view is seen only
  # with read access to its schema.
  defp can_see?(user, schema) when is_binary(schema) do
    case Brando.Authorization.Catalog.schema(schema) do
      nil -> not Engine.enabled?()
      module -> can_see?(user, module)
    end
  end

  defp can_see?(user, schema), do: Boundary.authorize(user, :read, schema) == :ok

  defp preload_creator({:ok, view}), do: {:ok, Repo.preload(view, :creator)}
  defp preload_creator(error), do: error

  # A failed query inside a transaction leaves the transaction usable
  defp savepoint, do: if(Repo.repo().in_transaction?(), do: [mode: :savepoint], else: [])

  # An environment that has not run the brando_215 migration has no views
  defp missing_table(%Postgrex.Error{postgres: %{code: :undefined_table, message: message}} = error, stacktrace, empty) do
    if String.contains?(message, "listing_view"), do: empty, else: reraise(error, stacktrace)
  end

  defp missing_table(error, stacktrace, _empty), do: reraise(error, stacktrace)
end

defmodule Brando.Pages do
  @moduledoc """
  Context for pages
  """
  use BrandoAdmin, :context
  use Brando.Query
  use Gettext, backend: Brando.Gettext

  import Ecto.Query

  alias Brando.Content.Blocks, as: ContentBlocks
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page
  alias Brando.Users.User
  alias Ecto.Changeset

  require Logger

  @type changeset :: Changeset.t()
  @type fragment :: Fragment.t()
  @type fragment_error :: {:error, {:fragment, :not_found}} | {:error, changeset}
  @type id :: binary | integer
  @type page :: Page.t()
  @type params :: map
  @type user :: User.t() | :system

  defmacro __using__(_) do
    quote do
      import Brando.Pages, only: [get_fragments: 1, render_fragment: 2, get_fragments: 2]
    end
  end

  query :list, Page do
    fn query -> from(q in query) end
  end

  filters Page do
    fn
      {:has_url, has_url}, query -> from q in query, where: q.has_url == ^has_url
      {:language, language}, query -> from q in query, where: q.language == ^language
      {:uri, uri}, query -> from q in query, where: ilike(q.uri, ^"%#{uri}%")
      {:title, title}, query -> from q in query, where: ilike(q.title, ^"%#{title}%")
      {:parents, true}, query -> from q in query, where: is_nil(q.parent_id)
    end
  end

  query :single, Page,
    do: fn query ->
      from q in query, preload: [:parent, :meta_image]
    end

  matches Page do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id

      {:language, language}, query ->
        from t in query,
          where: t.language == ^language

      {:key, key}, query ->
        from t in query,
          where: t.uri == ^key,
          preload: [fragments: ^build_fragments_query()]

      {:path, path}, query when is_list(path) ->
        from t in query,
          where: t.uri == ^Path.join(path),
          preload: [fragments: ^build_fragments_query()]

      {:path, path}, query ->
        from t in query,
          where: t.uri == ^path,
          preload: [fragments: ^build_fragments_query()]

      {:uri, uri}, query when is_list(uri) ->
        from t in query,
          where: t.uri == ^Path.join(uri),
          preload: [fragments: ^build_fragments_query()]

      {:uri, uri}, query ->
        from t in query,
          where: t.uri == ^uri,
          preload: [fragments: ^build_fragments_query()]

      {:has_url, has_url}, query ->
        from q in query, where: q.has_url == ^has_url
    end
  end

  mutation :create, Page do
    fn entry ->
      update_breadcrumbs(entry)
    end
  end

  mutation :update, Page do
    fn entry ->
      update_breadcrumbs(entry)
    end
  end

  @doc """
  Moves a page (the struct or its id) to the trash, deciding what becomes
  of its fragments in the same transaction. A fragment is found by its
  parent key, key and language, not through its page, so one left on a trashed page would keep showing on
  the site while the admin, which lists fragments under their page, no longer
  shows it.

  A page loaded in another environment raises `ArgumentError`
  (`Brando.Tenant.ensure_current!/1`): its id names another page here.

  `:fragments` takes:

    * `:move`, the default: to `fragment_target/1`, the nearest ancestor not
      in the trash, or else the homepage in the page's language. With
      neither, the fragments keep showing on the site with no page, listed
      under "Fragments without a page" (`list_fragments_without_page/1`).
    * `{:move, page_id}`: to that page, which must exist, be out of the trash
      and not be the page deleted. `{:move, nil}` leaves them with no page.
    * `:delete`: to the trash with the page, at its `deleted_at`. Restoring
      the page from the trash brings them back.

  A fragment already in the trash stays there, on the page. Moving takes the
  right to update each fragment, and deleting the right to delete it (and to
  publish it, for a published one), as `delete_fragment/2` asks; a fragment
  refused leaves the page where it was.

  Returns `{:error, {:fragments, :target_not_found}}` for a target page that
  can't take them, `{:error, {:fragments, :group_has_synchronized_members}}`
  when deleting would trash a fragment that is the source of synchronized
  translations (as `delete_fragment/2` refuses it), and
  `{:error, {:fragments, :invalid_choice}}` for another value of `:fragments`.
  """
  @spec delete_page(page | id, user, keyword) :: {:ok, page} | {:error, term}
  def delete_page(page_or_id, user \\ :system, opts \\ [])

  def delete_page(%Page{id: id} = page, user, opts) do
    Brando.Tenant.ensure_current!(page)
    delete_page(id, user, opts)
  end

  def delete_page(id, user, opts) do
    choice = Keyword.get(opts, :fragments, :move)

    with :ok <- valid_fragments_choice(choice),
         {:ok, {page, trashed}} <- delete_page_with_fragments(id, user, choice) do
      render_after_commit(trashed)
      {:ok, page}
    end
  end

  defp valid_fragments_choice(choice) when choice in [:move, :delete], do: :ok
  defp valid_fragments_choice({:move, _target}), do: :ok
  defp valid_fragments_choice(_), do: {:error, {:fragments, :invalid_choice}}

  # `Boundary.run` gives the fragments' work the delete's scope and
  # environment, and with group authorization its transaction. Without one
  # (legacy mode, `:system`) the transaction here holds it together.
  defp delete_page_with_fragments(id, user, choice) do
    Brando.Repo.transaction(fn ->
      user
      |> Brando.Authorization.Boundary.run(:delete, Page, fn _ -> delete_locked_page(id, user, choice) end)
      |> ok_or_rollback()
    end)
  end

  defp ok_or_rollback({:ok, result}), do: result
  defp ok_or_rollback({:error, reason}), do: Brando.Repo.rollback(reason)

  # Page deletes take the page tree's lock (`Brando.Pages.Page.PreventParentCycles`
  # takes it for a parent change) before anything else, so they run one at a
  # time: a second delete of the page finds it in the trash, and a delete of
  # the page the fragments go to finds them on it, or is found first. Holding
  # no row while it waits, it can't deadlock with them or with a save.
  #
  # The fragments are moved, or cleared for the trash, before the generated
  # delete runs: a fragment refused stops it before it tells anyone.
  defp delete_locked_page(id, user, choice) do
    lock_page_tree()

    with %Page{} = page <- live_page(id) || {:error, {:page, :not_found}},
         {:ok, prepared} <- prepare_fragments(lock_fragments(page), page, user, choice) do
      Brando.Query.Mutations.delete(__MODULE__, Page, "page", page.id,
        user: user,
        callback: &page_deleted(&1, user, prepared)
      )
    end
  end

  defp lock_fragments(page) do
    Brando.Repo.all(
      from f in Fragment,
        where: f.page_id == ^page.id and is_nil(f.deleted_at),
        order_by: [asc: f.id],
        lock: "FOR UPDATE"
    )
  end

  # A trail leaves out a deleted parent: the live descendants' trails drop
  # the trashed page
  defp page_deleted(page, user, {kind, fragments}) do
    keep_apart_from_page(page)

    with {:ok, trashed} <- if(kind == :trash, do: trash_fragments(fragments, page, user), else: {:ok, []}) do
      update_descendant_breadcrumbs(page)
      Brando.Cache.Query.evict_all(Page)
      fragments_left(kind, fragments, trashed)
      {:ok, {page, trashed}}
    end
  end

  defp fragments_left(_kind, [], _trashed), do: :ok

  defp fragments_left(kind, fragments, trashed) do
    Brando.Cache.Query.evict_all(Fragment)
    if kind == :trash, do: broadcast_fragments(trashed, :deleted), else: broadcast_fragments(fragments, :updated)
  end

  # As a fragment's own save or delete tells its open forms and frontend
  # edit, once committed
  defp broadcast_fragments(fragments, action) do
    topic = Brando.Tenant.Topic.scoped("brando:mutations:#{inspect(Fragment)}")

    Enum.each(fragments, fn fragment ->
      Brando.Repo.after_commit(fn ->
        Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {:mutation, Fragment, fragment, action})
      end)
    end)
  end

  # A restore brings back the fragments on the page trashed at its own
  # `deleted_at`, stored to the second. One trashed on its own in that second
  # is set a second earlier, with its notes, so it stays in the trash.
  defp keep_apart_from_page(%Page{id: id, deleted_at: deleted_at}) do
    earlier = DateTime.add(deleted_at, -1)

    {_, ids} =
      Brando.Repo.update_all(
        from(f in Fragment, where: f.page_id == ^id and f.deleted_at == ^deleted_at, select: f.id),
        set: [deleted_at: earlier]
      )

    Brando.Notes.entries_trash_moved(Fragment, ids, deleted_at, earlier)
  end

  # `{:moved, fragments}` once moved, `{:trash, fragments}` once each may be
  # trashed: that waits for the page's `deleted_at`
  defp prepare_fragments([], _page, _user, _choice), do: {:ok, {:moved, []}}
  defp prepare_fragments(fragments, page, user, :move), do: move_fragments(fragments, fragment_target(page), user)
  defp prepare_fragments(fragments, _page, user, {:move, nil}), do: move_fragments(fragments, nil, user)

  defp prepare_fragments(fragments, page, user, {:move, target_id}) do
    case Ecto.Type.cast(:id, target_id) do
      {:ok, id} when id != page.id -> move_fragments(fragments, id, user)
      _ -> {:error, {:fragments, :target_not_found}}
    end
  end

  defp prepare_fragments(fragments, _page, user, :delete) do
    fragments
    |> each_fragment(fn fragment ->
      with :ok <- Brando.Authorization.Boundary.authorize(user, :delete, fragment),
           :ok <- authorize_fragment_publish(user, fragment),
           :ok <- guard_fragment_delete(fragment),
           do: {:ok, fragment}
    end)
    |> case do
      {:ok, fragments} -> {:ok, {:trash, fragments}}
      error -> error
    end
  end

  @doc """
  Takes the current environment's page tree lock for the rest of the
  transaction, as a page's delete and a parent change take it before any
  row. A caller that locks pages itself and then deletes one takes it first.
  """
  @spec lock_page_tree() :: :ok
  def lock_page_tree do
    prefix = Brando.Tenant.current_prefix() || "public"

    Ecto.Adapters.SQL.query!(Brando.Repo.repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "brando-page-tree:" <> prefix
    ])

    :ok
  end

  defp live_page(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} -> Brando.Repo.one(from p in Page, where: p.id == ^id and is_nil(p.deleted_at))
      :error -> nil
    end
  end

  # To no page (`nil`); to the default target, which with the page trashed
  # meanwhile is no page; or to the page `id`, refused when it can't take them
  defp move_fragments(fragments, nil, user), do: move_fragments_to(fragments, nil, user)

  defp move_fragments(fragments, %Page{id: id}, user),
    do: move_fragments_to(fragments, live_page(id), user)

  defp move_fragments(fragments, id, user) do
    case live_page(id) do
      nil -> {:error, {:fragments, :target_not_found}}
      target -> move_fragments_to(fragments, target, user)
    end
  end

  # A move changes the page the admin lists them under, and the fragments a
  # page loaded with its own (`get_fragment/2`) holds; templates find them
  # by their keys as before
  defp move_fragments_to(fragments, target, user) do
    target_id = target && target.id

    fragments
    |> each_fragment(fn fragment ->
      changeset = Changeset.change(fragment, page_id: target_id)

      with :ok <- Brando.Authorization.Boundary.authorize(user, :update, fragment),
           :ok <- Brando.Authorization.Boundary.change(user, :update, changeset),
           {:ok, moved} <- Brando.Repo.update(changeset) do
        # In its history, and as the save open editors are told of
        Brando.Activity.saved(changeset, moved, user)
        {:ok, moved}
      end
    end)
    |> case do
      {:ok, moved} -> {:ok, {:moved, moved}}
      error -> error
    end
  end

  # At the page's own `deleted_at`, which `restore_fragments/2` matches on
  defp trash_fragments(fragments, page, user) do
    each_fragment(fragments, fn fragment ->
      with {:ok, trashed} <- fragment |> Changeset.change(deleted_at: page.deleted_at) |> Brando.Repo.update() do
        Brando.Activity.deleted(trashed, user, true)
        Brando.Notes.entry_deleted(Fragment, trashed, true)
        {:ok, trashed}
      end
    end)
  end

  # A direct delete's guard: the source of synchronized translations stays
  defp guard_fragment_delete(fragment) do
    case Brando.Translations.guard_delete(Fragment, fragment) do
      :ok -> :ok
      {:error, reason} -> {:error, {:fragments, reason}}
    end
  end

  defp authorize_fragment_publish(user, %Fragment{status: :published} = fragment),
    do: Brando.Authorization.Boundary.authorize(user, :publish, fragment)

  defp authorize_fragment_publish(_user, _fragment), do: :ok

  defp each_fragment(fragments, fun) do
    fragments
    |> Enum.reduce_while({:ok, []}, fn fragment, {:ok, acc} ->
      case fun.(fragment) do
        {:ok, done} -> {:cont, {:ok, [done | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      error -> error
    end
  end

  # Entries embedding a fragment that left the site or came back render
  # again, as after `delete_fragment/2`
  defp fragments_changed(fragments) do
    Enum.each(fragments, &ContentBlocks.render_entries_with_fragment_id(&1.id))
  end

  @doc """
  Where `delete_page/3` moves the fragments of `page` by default: its nearest
  ancestor that is not in the trash, or else the homepage in its language
  (when that is another page). `nil` when there is neither.
  """
  @spec fragment_target(page) :: page | nil
  def fragment_target(%Page{} = page) do
    nearest_live_ancestor(page, MapSet.new([page.id])) || other_homepage(page)
  end

  # `seen` ends the walk at a parent cycle stored before they were refused
  defp nearest_live_ancestor(%Page{parent_id: nil}, _seen), do: nil

  defp nearest_live_ancestor(%Page{parent_id: parent_id}, seen) do
    if MapSet.member?(seen, parent_id) do
      nil
    else
      case Brando.Repo.get(Page, parent_id) do
        nil -> nil
        %Page{deleted_at: nil} = parent -> parent
        parent -> nearest_live_ancestor(parent, MapSet.put(seen, parent.id))
      end
    end
  end

  defp other_homepage(%Page{id: id, language: language}) do
    Brando.Repo.one(
      from p in Page,
        where: p.is_homepage and p.language == ^language and is_nil(p.deleted_at) and p.id != ^id,
        order_by: [asc: p.id],
        limit: 1
    )
  end

  @doc """
  Brings back from the trash the fragments trashed with `page` (by
  `delete_page/3` with `fragments: :delete`): those still on it with the
  page's `deleted_at` (a fragment trashed on its own in that second was set
  a second earlier). `page` is the page as it was in the trash.
  `Brando.Authorization.Boundary.restore/2` calls this in the page's
  restore, in its transaction. Each fragment takes the right to restore it.
  Entries embedding them are queued for rendering once the transaction
  around the call commits.
  """
  def restore_fragments(%Page{id: id, deleted_at: %{} = deleted_at}, user) do
    fragments =
      Brando.Repo.all(
        from f in Fragment,
          where: f.page_id == ^id and f.deleted_at == ^deleted_at,
          order_by: [asc: f.id]
      )

    result =
      each_fragment(fragments, fn fragment ->
        with :ok <- Brando.Authorization.Boundary.authorize(user, :restore, fragment),
             {:ok, restored} <- Brando.Repo.restore(fragment) do
          Brando.Activity.restored(restored, user)
          Brando.Notes.entry_restored(Fragment, fragment)
          {:ok, restored}
        end
      end)

    with {:ok, restored} <- result do
      if restored != [], do: Brando.Cache.Query.evict_all(Fragment)
      render_after_commit(restored)
      {:ok, restored}
    end
  end

  def restore_fragments(%Page{}, _user), do: {:ok, []}

  # A page's delete or restore, or a transaction around it, may still roll
  # back: its renders wait for the commit, in its site and environment, after
  # the caches it evicts. Keyed per call: a page id repeats across sites, and
  # in a second restore of the page in the transaction.
  defp render_after_commit([]), do: :ok

  defp render_after_commit(fragments) do
    render = Brando.Tenant.capture_context(fn -> fragments_changed(fragments) end)
    Brando.Repo.after_commit({__MODULE__, :fragments_restored, make_ref()}, render, late: true)
  end

  @doc """
  The fragments not in the trash that no page in the admin lists: their page
  is in the trash or gone, or they never had one. They still render on the
  site. The pages listing shows them under "Fragments without a page", in
  its content language: pass `language` for those in one language.
  """
  @spec list_fragments_without_page(String.t() | atom | nil) :: [fragment]
  def list_fragments_without_page(language \\ nil) do
    query =
      from f in Fragment,
        left_join: p in Page,
        on: p.id == f.page_id,
        where: is_nil(f.deleted_at) and (is_nil(p.id) or not is_nil(p.deleted_at)),
        order_by: [asc: f.parent_key, asc: f.key, asc: f.language, asc: f.id]

    query = if language, do: where(query, [f], f.language == ^to_string(language)), else: query

    query
    |> Brando.Authorization.Boundary.query(Fragment)
    |> Brando.Repo.all()
  end

  mutation :duplicate,
           {Page,
            delete_fields: [
              :parent
            ],
            change_fields: [
              :uri,
              :title,
              children: &__MODULE__.duplicate_children/2,
              alternates: [],
              alternate_entries: [],
              vars: &__MODULE__.duplicate_vars/2,
              fragments: &__MODULE__.duplicate_fragments/2
            ]}

  def duplicate_vars(entry, _) do
    entry
    |> Brando.Repo.preload(:vars)
    |> Map.get(:vars)
    |> Enum.map(fn var ->
      var
      |> Map.merge(%{
        id: nil,
        page_id: nil,
        block_id: nil,
        module_id: nil,
        global_set_id: nil,
        table_row_id: nil,
        menu_item_id: nil,
        inserted_at: nil,
        updated_at: nil
      })
      |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
    end)
  end

  def duplicate_fragments(entry, _) do
    entry
    |> Brando.Repo.preload(
      fragments: [
        entry_blocks: [
          block: [:vars, :children, refs: Brando.Content.Ref.preloads()]
        ]
      ]
    )
    |> Map.get(:fragments)
    |> Enum.map(&duplicate_fragment/1)
  end

  defp duplicate_fragment(fragment) do
    # Duplicate entry_blocks for the fragment
    duplicated_entry_blocks =
      Enum.map(fragment.entry_blocks, fn entry_block ->
        entry_block
        |> Map.merge(%{
          id: nil,
          entry_id: nil,
          block_id: nil,
          inserted_at: nil,
          updated_at: nil
        })
        |> Map.put(:block, duplicate_block(entry_block.block))
        |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
      end)

    fragment
    |> Map.merge(%{
      id: nil,
      page_id: nil,
      inserted_at: nil,
      updated_at: nil,
      entry_blocks: duplicated_entry_blocks
    })
    |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
  end

  defp duplicate_block(block) do
    %{
      block
      | id: nil,
        uid: Brando.Utils.generate_uid(),
        vars: Enum.map(block.vars || [], &duplicate_block_var/1),
        children: Enum.map(block.children || [], &duplicate_block/1),
        refs: duplicate_refs(block.refs || []),
        creator: nil,
        fragment: nil,
        module: nil,
        identifiers: nil,
        inserted_at: nil,
        updated_at: nil
    }
    |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
  end

  defp duplicate_block_var(var) do
    %{var | id: nil, inserted_at: nil, updated_at: nil}
    |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
  end

  defp duplicate_refs(refs) do
    Enum.map(refs, fn ref ->
      ref
      |> Map.merge(%{
        id: nil,
        block_id: nil,
        uid: Brando.Utils.generate_uid(),
        inserted_at: nil,
        updated_at: nil
      })
      |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
    end)
  end

  def duplicate_children(entry, _) do
    entry
    |> Brando.Repo.preload(
      children: [
        :vars,
        entry_blocks: [
          block: [:vars, :children, refs: Brando.Content.Ref.preloads()]
        ],
        fragments: [
          entry_blocks: [
            block: [:vars, :children, refs: Brando.Content.Ref.preloads()]
          ]
        ]
      ]
    )
    |> Map.get(:children)
    |> Enum.map(&duplicate_child_page/1)
  end

  defp duplicate_child_page(child) do
    # Duplicate the child page's entry_blocks
    duplicated_entry_blocks =
      Enum.map(child.entry_blocks, fn entry_block ->
        entry_block
        |> Map.merge(%{
          id: nil,
          entry_id: nil,
          block_id: nil,
          inserted_at: nil,
          updated_at: nil
        })
        |> Map.put(:block, duplicate_block(entry_block.block))
        |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
      end)

    # Duplicate the child page's vars
    duplicated_vars =
      Enum.map(child.vars || [], fn var ->
        var
        |> Map.merge(%{
          id: nil,
          page_id: nil,
          block_id: nil,
          module_id: nil,
          global_set_id: nil,
          table_row_id: nil,
          menu_item_id: nil,
          inserted_at: nil,
          updated_at: nil
        })
        |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
      end)

    # Duplicate the child page's fragments
    duplicated_fragments = Enum.map(child.fragments || [], &duplicate_fragment/1)

    child
    |> Map.merge(%{
      id: nil,
      parent_id: nil,
      inserted_at: nil,
      updated_at: nil,
      entry_blocks: duplicated_entry_blocks,
      vars: duplicated_vars,
      fragments: duplicated_fragments,
      children: [],
      alternates: [],
      alternate_entries: []
    })
    |> Map.update(:uri, child.uri, fn uri -> "#{uri}-copy" end)
    |> Map.update(:title, child.title, fn title -> "#{title} #{gettext("(copy)")}" end)
    |> Map.put(:status, :draft)
    |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
  end

  @doc """
  Only gets schemas that are parents
  """
  def only_parents(query), do: from(m in query, where: is_nil(m.parent_id))

  @doc """
  List page parents
  """
  def list_parents do
    no_value = %{value: nil, name: "–"}

    parents =
      Page
      |> only_parents()
      |> exclude_deleted()
      |> Brando.Repo.all()

    val =
      if parents do
        parents
        |> Enum.reverse()
        |> Enum.reduce([no_value], fn parent, acc ->
          acc ++ [%{value: parent.id, name: "#{parent.uri} (#{parent.language})"}]
        end)
      else
        [no_value]
      end

    {:ok, val}
  end

  @doc """
  Lists the page templates of the current site (`Brando.Site.Frontend.page_html/0`):
  the functions of its `PageHTML`, or a legacy `PageView`'s templates. A site
  with no frontend module has none.
  """
  def list_templates do
    case Brando.Site.Frontend.page_html() do
      nil -> {:ok, []}
      module -> {:ok, templates_of(module)}
    end
  end

  defp templates_of(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__templates__, 0) do
      {_, _, templates} = module.__templates__()
      Enum.reject(templates, &String.starts_with?(&1, "_"))
    else
      :functions
      |> module.__info__()
      |> Enum.map(fn {fun, _arity} -> to_string(fun) end)
      |> Enum.reject(&String.starts_with?(&1, "__"))
      |> Enum.map(&(&1 <> ".html"))
    end
  end

  query :list, Fragment do
    fn query ->
      from q in query,
        order_by: [asc: q.parent_key, asc: q.sequence, asc: q.language, asc: q.id]
    end
  end

  filters Fragment do
    fn
      {:title, title}, query ->
        from q in query, where: ilike(q.title, ^"%#{title}%")

      {:language, language}, query ->
        from q in query, where: q.language == ^language

      {:parent_key, parent_key}, query ->
        from q in query, where: q.parent_key == ^parent_key
    end
  end

  query :single, Fragment, do: fn query -> from(q in query) end

  matches Fragment do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id

      {:language, language}, query ->
        from t in query,
          where: t.language == ^language

      {:key, key}, query ->
        from t in query,
          where: t.key == ^key

      {:parent_key, parent_key}, query ->
        from t in query,
          where: t.parent_key == ^parent_key
    end
  end

  mutation :create, Fragment

  mutation :update, Fragment do
    fn fragment ->
      ContentBlocks.render_entries_with_fragment_id(fragment.id)
      {:ok, fragment}
    end
  end

  mutation :delete, Fragment do
    fn fragment ->
      ContentBlocks.render_entries_with_fragment_id(fragment.id)
      {:ok, fragment}
    end
  end

  mutation :duplicate, {Fragment, delete_fields: [], change_fields: [:key]}

  @doc """
  Find fragment with `id` in `fragments`
  """
  def find_fragment(fragments, id) do
    fragments
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> {:error, {:fragment, :not_found, id}}
      mod -> {:ok, mod}
    end
  end

  @doc """
  Get set of fragments by parent key.

  For public pages: an unpublished fragment keeps its key, with no content, so
  it renders nothing however a template reads it. `status: :published` is the
  same. Pass another `:status`, such as `status: :all`, for fragments as stored.
  """
  def get_fragments(parent_key) when is_binary(parent_key) do
    IO.warn("get_fragments(binary) is deprecated! Use `get_fragments(map)` instead")
    get_fragments(%{filter: %{parent_key: parent_key}})
  end

  def get_fragments(%{status: status} = opts) when status not in [:published, "published"] do
    {:ok, fragments} = list_fragments(opts)
    {:ok, Map.new(fragments, fn x -> {x.key, x} end)}
  end

  def get_fragments(opts) when is_map(opts) do
    {:ok, fragments} = opts |> Map.delete(:status) |> select_status() |> list_fragments()
    {:ok, public_fragments(fragments)}
  end

  defp select_status(%{select: {kind, fields}} = opts) when kind in [:map, :struct, :raw] and is_list(fields),
    do: %{opts | select: {kind, Enum.uniq([:status | fields])}}

  defp select_status(%{select: fields} = opts) when is_list(fields), do: %{opts | select: Enum.uniq([:status | fields])}
  defp select_status(opts), do: opts

  defp public_fragments(fragments), do: Map.new(fragments, &{&1.key, without_draft_content(&1)})

  defp without_draft_content(%{status: :published} = fragment), do: fragment
  defp without_draft_content(%{rendered_blocks: _} = fragment), do: %{fragment | rendered_blocks: nil}
  defp without_draft_content(fragment), do: fragment

  @doc """
  Get fragment from page
  """
  def get_fragment(%Page{fragments: %Ecto.Association.NotLoaded{}} = page, key) do
    page = Brando.Repo.preload(page, [:fragments])
    Enum.find(page.fragments, &(&1.key == key))
  end

  def get_fragment(%Page{fragments: fragments}, key) do
    Enum.find(fragments, &(&1.key == key))
  end

  @doc """
  Rerender all fragments
  """
  def rerender_fragments do
    {:ok, fragments} = list_fragments()
    ContentBlocks.render_entries(Fragment, Enum.map(fragments, & &1.id))
  end

  def rerender_fragment(id) do
    ContentBlocks.render_entry(Fragment, id)
  end

  def list_fragments_translations(parent_key, opts \\ []) do
    exclude_lang = Keyword.get(opts, :exclude_language)

    query =
      Fragment
      |> where([p], p.parent_key == ^parent_key)
      |> exclude_deleted()
      |> order_by([p], [:sequence, :key, :id])

    query =
      if exclude_lang do
        where(query, [p], p.language != ^exclude_lang)
      else
        query
      end

    fragments = Brando.Repo.all(query)

    # group keys as "key -> [fragment, fragment2]
    split_fragments = Brando.Utils.split_by(fragments, :key)
    {:ok, split_fragments}
  end

  @doc """
  Get set of fragments by parent key and language, for public pages: an
  unpublished fragment has no content, as with `get_fragments/1`.
  """
  def get_fragments(parent_key, language) do
    Fragment
    |> where([p], p.parent_key == ^parent_key)
    |> where([p], p.language == ^language)
    |> exclude_deleted()
    |> Brando.Repo.all()
    |> public_fragments()
  end

  @doc """
  Get a var from Page.

  Returns the rendered value of the var. Vars are an association: load the
  page with `preload: [:vars]`, as in

      Pages.get_page(%{matches: %{path: path}, preload: [:alternate_entries, :vars]})

  A page whose vars are not loaded raises an `ArgumentError` saying so.
  """
  @spec get_var(page, binary) :: any
  def get_var(%Page{vars: %Ecto.Association.NotLoaded{}} = page, _), do: raise_vars_not_loaded(page)
  def get_var(%Page{vars: nil}, _), do: nil

  def get_var(%Page{vars: vars}, var_key) do
    case Enum.find(vars, &(&1.key == var_key)) do
      nil -> nil
      var -> Brando.Content.render_var(var)
    end
  end

  def get_var(_, _), do: nil

  @doc """
  Checks if page has var. Like `get_var/2`, it needs the page's vars preloaded.
  """
  @spec has_var?(page, binary) :: boolean
  def has_var?(%Page{vars: %Ecto.Association.NotLoaded{}} = page, _), do: raise_vars_not_loaded(page)
  def has_var?(%Page{vars: nil}, _), do: false
  def has_var?(%Page{vars: vars}, var), do: Enum.any?(vars, &(&1.key == var))

  defp raise_vars_not_loaded(page) do
    raise ArgumentError, """
    the page vars are not loaded (page #{inspect(page.id)}, #{inspect(page.uri)}).

    Page vars are an association since Brando 0.54. Load the page with them, for example
    `Brando.Pages.get_page(%{matches: ..., preload: [:alternate_entries, :vars]})`,
    or `Brando.Repo.preload(page, :vars)`.
    """
  end

  @doc """
  Fetch a page fragment by `key`.

  ## Example:

      fetch_fragment("my/fragment", Gettext.get_locale(MyApp.Gettext)
      fetch_fragment("my/fragment", "en")

  If no language is passed, default language set in `brando.exs` will be used.
  If the fragment isn't found, it renders an error box in development; elsewhere
  it renders nothing and is logged. An unpublished fragment renders nothing.
  """
  def fetch_fragment(key, language \\ nil) when is_binary(key) do
    language = language || Brando.Languages.default_language()

    fragment =
      Brando.Repo.one(
        from p in Fragment,
          where: p.key == ^key and p.language == ^language and is_nil(p.deleted_at)
      )

    case fragment do
      nil ->
        missing_fragment_html(key: key, lang: language)

      fragment ->
        fragment_html(fragment)
    end
  end

  @doc """
  Render a fragment, or the fragment under `key` in a map from `get_fragments/1`,
  or the one with `parent` key and `key`. An unpublished fragment renders nothing.
  A missing one renders an error box in development; elsewhere it renders nothing
  and is logged.
  """
  def render_fragment(%Fragment{} = fragment), do: fragment_html(fragment)

  def render_fragment(fragments, key) when is_map(fragments) do
    case Map.get(fragments, key) do
      nil ->
        missing_fragment_html(key: key, frags: Map.keys(fragments))

      fragment ->
        fragment_html(fragment)
    end
  end

  def render_fragment(parent, key, language \\ nil) when is_binary(parent) and is_binary(key) do
    case lookup_fragment(parent, key, language) do
      {:ok, fragment} -> fragment_html(fragment)
      {:error, {:fragment, :not_found}} -> missing_fragment_html(parent: parent, key: key, lang: language)
    end
  end

  @doc """
  `render_fragment/3` for HTML stored with an entry, as the `{% fragment %}`
  tag renders it.
  """
  def render_embedded_fragment(parent, key, language \\ nil) when is_binary(parent) and is_binary(key) do
    case lookup_fragment(parent, key, language) do
      # Block code embeds the fragment before the entry's Liquid pass. The
      # fragment has had its own, so its text must not be evaluated again.
      {:ok, fragment} ->
        {:safe, html} = fragment_html(fragment)
        {:safe, Brando.Villain.InertLiquid.encode(html)}

      {:error, {:fragment, :not_found}} ->
        missing_fragment_html(parent: parent, key: key, lang: language)
    end
  end

  defp lookup_fragment(parent, key, language) do
    matches = %{parent_key: parent, key: key}
    matches = if language, do: Map.put(matches, :language, language), else: matches
    get_fragment(%{matches: matches})
  end

  # A diagnostic for whoever writes the template, which visitors never see. The
  # keys are what an editor typed, or what the template passes along.
  defp missing_fragment_html(details) do
    if Brando.env() == :dev do
      rows = Enum.map_join(details, "<br />\n", &missing_fragment_row/1)

      Phoenix.HTML.raw(~s(<div class="page-fragment-missing text-mono">
             <strong>Missing page fragment</strong> <br />
#{rows}
           </div>))
    else
      Logger.warning("Missing page fragment #{inspect(details)}")
      Phoenix.HTML.raw("")
    end
  end

  defp missing_fragment_row({label, value}) do
    value = if is_list(value), do: inspect(value), else: value

    "             #{String.pad_trailing(to_string(label), 6, ".")}: #{value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()}"
  end

  # rendered_blocks is pre-rendered CMS content from our own rendering pipeline
  # nosec
  defp fragment_html(%Fragment{status: :published} = fragment),
    do: fragment |> Brando.FrontendEdit.rendered_html(:blocks) |> Phoenix.HTML.raw()

  defp fragment_html(%Fragment{}), do: {:safe, ""}

  @doc """
  Compute and store breadcrumbs for a page and its descendants.

  Breadcrumbs are stored as a list of `%{"title" => ..., "uri" => ...}` maps
  representing the path from the root page down to the current page.
  """
  def update_breadcrumbs(%Page{} = page), do: update_breadcrumbs(page, MapSet.new())

  defp update_breadcrumbs(page, seen) do
    page = Brando.Repo.preload(page, [:parent], force: true)
    breadcrumbs = build_breadcrumbs(page)

    page
    |> Changeset.change(%{breadcrumbs: breadcrumbs})
    |> Brando.Repo.update()
    |> case do
      {:ok, updated_page} ->
        update_descendant_breadcrumbs(updated_page, seen)
        {:ok, updated_page}

      error ->
        error
    end
  end

  @doc """
  Bring the trails of a restored page and its live descendants up to date:
  each of them takes the page back in. `Brando.Authorization.Boundary.restore/2`
  calls this in the restore's transaction, and
  `Brando.Revisions.set_entry_to_revision/5` in a revision restore's, which
  would otherwise bring back the trail the revision holds.
  """
  def restored(%Page{} = page) do
    with {:ok, page} <- update_breadcrumbs(page) do
      Brando.Cache.Query.evict_all(Page)
      {:ok, page}
    end
  end

  @doc """
  Compute and store breadcrumbs for every page in `language` that is not
  deleted, under the current site and environment, a page under a deleted
  parent included.
  """
  def update_breadcrumbs_for_language(language) do
    Page
    |> where([p], p.language == ^language and is_nil(p.deleted_at))
    |> Brando.Repo.all()
    |> Enum.each(&store_breadcrumbs/1)

    Brando.Cache.Query.evict_all(Page)
  end

  # One page that can't take a trail is logged: the others still get theirs
  defp store_breadcrumbs(page) do
    page = Brando.Repo.preload(page, [:parent])
    {:ok, _} = page |> Changeset.change(%{breadcrumbs: build_breadcrumbs(page)}) |> Brando.Repo.update()
  rescue
    error ->
      Logger.error(
        "[Brando.Pages] Computing the breadcrumbs of page #{page.id} again failed: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )
  end

  defp build_breadcrumbs(%Page{is_homepage: true}) do
    []
  end

  defp build_breadcrumbs(%Page{} = page) do
    home_entry = %{"title" => Brando.Sites.site_name(page.language), "uri" => "/"}
    ancestors = collect_ancestors(page, [], MapSet.new([page.id]))

    trail =
      Enum.map(ancestors ++ [page], fn
        %Page{uri: uri} = p -> %{"title" => p.title, "uri" => "/" <> uri}
      end)

    [home_entry | trail]
  end

  # `seen` holds the pages already on the trail: a parent cycle stored
  # before cycles were refused ends the trail where it closes
  defp collect_ancestors(%Page{parent_id: nil}, acc, _seen), do: acc

  defp collect_ancestors(%Page{parent: %Ecto.Association.NotLoaded{}} = page, acc, seen) do
    page = Brando.Repo.preload(page, [:parent])
    collect_ancestors(page, acc, seen)
  end

  defp collect_ancestors(%Page{parent: nil}, acc, _seen), do: acc

  # A deleted parent has no address (its uri is obfuscated until it is
  # restored), so the trail goes past it
  defp collect_ancestors(%Page{parent: parent}, acc, seen) do
    if MapSet.member?(seen, parent.id) do
      acc
    else
      parent = Brando.Repo.preload(parent, [:parent])
      collect_ancestors(parent, if(parent.deleted_at, do: acc, else: [parent | acc]), MapSet.put(seen, parent.id))
    end
  end

  # A deleted child keeps its stored trail, but the walk goes through it: the
  # live pages under it have trails too. `seen` holds the pages the walk came
  # down through, so a parent cycle ends it.
  defp update_descendant_breadcrumbs(%Page{} = page, seen \\ MapSet.new()) do
    if MapSet.member?(seen, page.id) do
      :ok
    else
      seen = MapSet.put(seen, page.id)

      Page
      |> where([p], p.parent_id == ^page.id)
      |> Brando.Repo.all()
      |> Enum.each(&update_trail(&1, seen))
    end
  end

  defp update_trail(page, seen \\ MapSet.new())
  defp update_trail(%Page{deleted_at: nil} = page, seen), do: update_breadcrumbs(page, seen)
  defp update_trail(page, seen), do: update_descendant_breadcrumbs(page, seen)

  @doc """
  Called by the trash purge (`Brando.SoftDelete.Query.clean_up_soft_deletions/0`)
  in its transaction, before it deletes the expired rows `ids` of `schema`.
  For pages, the child pages and fragments that remain lose the reference,
  which would block the delete, and the children's trails are recomputed.
  """
  def before_purge(Page, ids) do
    Fragment |> where([f], f.page_id in ^ids) |> Brando.Repo.update_all(set: [page_id: nil])

    {_, children} =
      Page
      |> where([p], p.parent_id in ^ids and p.id not in ^ids)
      |> select([p], p)
      |> Brando.Repo.update_all(set: [parent_id: nil])

    Enum.each(children, &update_trail/1)
    Brando.Cache.Query.evict_all(Page)
    Brando.Cache.Query.evict_all(Fragment)
  end

  def before_purge(_schema, _ids), do: :ok

  defp build_fragments_query do
    from f in Fragment,
      where: is_nil(f.deleted_at),
      order_by: [asc: f.sequence, asc: f.key, asc: f.id]
  end
end

defmodule Brando.Query.Runtime do
  @moduledoc """
  Internal runtime implementation for the public `Brando.Query` API.

  # Mutations

      ```
      mutation :create, Post
      mutation :update, Post
      mutation :delete, Post
      mutation :duplicate, {
        Post,
        change_fields: [:title],
        delete_fields: [:comments],
        merge_fields: %{contributors: []}
      }
      ```

  You can pass a function to execute after the mutation is finished:

      ```
      mutation :create, Post do
        fn entry ->
          {:ok, entry}
        end
      end
      ```

  You can pass preloads to the mutations:

      ```
      mutation :update, {Project, preload: [:tags]}
      ```

  For `create` operations, the preloads will execute after insertion
  For `update` operations, the preloads will execute on fetching entry for update

  This can be useful if your `identifier` function references associations on the entry

  # Select

  ## Examples

      {:ok, posts} = list_posts(%{select: [:slug, :updated_at]})

  Default format, returns a map with `:slug` and `updated_at` keys.

      {:ok, posts} = list_posts(%{select: {:struct, [:slug, :updated_at]}})

  Returns a struct with `:slug` and `updated_at` keys.

      {:ok, posts} = list_posts(%{select: {:map, [:slug, :updated_at]}})

  Same as the default format, only explicitly marked parameters.


  # Order

  ## Examples

        {:ok, posts} = list_posts(%{order: [{:asc, :title}]})

  Orders by `:title` on joined table `:comments`

        {:ok, posts} = list_posts(%{order: [{:asc, {:comments, :title}]})

  or

        {:ok, posts} = list_posts(%{order: "asc comments.title"})


  # Preload

  ## Examples

  Preloads comments association:

      {:ok, results} = list_posts(%{preload: [:comments]})

  For simple ordering of the preload association, you can use
  a more complex setup of `{key, {schema, [direction: sort_key]}}`. For instance:

      {:ok, results} = list_posts(%{
        preload: [
          {:comments, {Comment, [desc: :inserted_at]}}
        ]
      })

  For slightly more advances ordered preloads you can supply a map:

      {:ok, results} = list_posts(%{
        preload: [
          fragments: %{
            module: Fragment,
            order: [asc: :sequence],
            preload: [creator: :avatar],
            hide_deleted: true
          }
        ]
      })

  You can also supply a preorder query directly:

      {:ok, results} = list_posts(%{preload: [{:comments, from(c in Comment, order_by: c.inserted_at)}]})


  # Cache

  ## Examples

      {:ok, results} = list_posts(%{status: :published, cache: true})
      {:ok, results} = list_posts(%{status: :published, cache: {:ttl, :timer.minutes(15)}})

  """

  import Ecto.Query

  alias Brando.Cache
  alias Brando.Repo
  alias Brando.Revisions

  def with_order(query, order) when is_list(order) do
    Enum.reduce(order, query, fn
      {:array_position, ids}, query ->
        order_by(query, [q], fragment("array_position(?, ?)", ^ids, q.id))

      {_, {:array_position, ids}}, query ->
        order_by(query, [q], fragment("array_position(?, ?)", ^ids, q.id))

      {_, :status}, query ->
        query
        |> order_by(fragment("status=0 DESC"))
        |> order_by(fragment("status=2 DESC"))
        |> order_by(fragment("status=1 DESC"))
        |> order_by(fragment("status=3 DESC"))

      {_, :random}, query ->
        query |> order_by(fragment("RANDOM()"))

      {modulo, :modulo}, query ->
        order_by(
          query,
          [q],
          fragment(
            "(extract(epoch from ?) * 100000)::bigint % ?",
            field(q, :inserted_at),
            ^modulo
          )
        )

      {dir, {join_assoc_1, join_assoc_2, order_field}}, query ->
        from(
          q in query,
          left_join: j in assoc(q, ^join_assoc_1),
          left_join: j2 in assoc(j, ^join_assoc_2),
          order_by: [{^dir, field(j2, ^order_field)}]
        )

      {dir, {join_assoc, order_field}}, query ->
        from(
          q in query,
          left_join: j in assoc(q, ^join_assoc),
          order_by: [{^dir, field(j, ^order_field)}],
          preload: [{^join_assoc, j}]
        )

      {dir, by}, query ->
        query |> order_by({^dir, ^by})
    end)
  end

  def with_order(query, order_string) when is_binary(order_string) do
    order_list = order_string_to_list(order_string)
    with_order(query, order_list)
  end

  def with_order(query, order), do: with_order(query, [order])

  def order_string_to_list(order_string) when is_binary(order_string) do
    order_string
    |> String.split(",")
    |> Enum.map(fn e ->
      e |> String.trim() |> String.split(" ") |> Enum.map(&parse_order_segment/1) |> List.to_tuple()
    end)
  end

  def order_string_to_list(order_list) when is_list(order_list) do
    order_list
  end

  defp parse_order_segment(val) do
    case String.split(val, ".") do
      [v1, v2, v3] -> {String.to_atom(v1), String.to_atom(v2), String.to_atom(v3)}
      [v1, v2] -> {String.to_atom(v1), String.to_atom(v2)}
      [val] -> String.to_atom(val)
    end
  end

  def with_select(query, {:map, fields}), do: from(q in query, select: map(q, ^fields))
  def with_select(query, {:struct, fields}), do: from(q in query, select: ^fields)
  def with_select(query, {:raw, fields}), do: from(q in query, select: ^fields)
  def with_select(query, fields), do: from(q in query, select: map(q, ^fields))

  # def with_exclude(query, fields),
  #   do: from(q in query, select: %{q | Keyword.from_keys(fields, nil)})

  def with_status(query, "all"), do: query

  def with_status(query, "deleted"),
    do: query

  def with_status(query, "published_and_pending"),
    do:
      from(q in query,
        where: q.status in [1, 2]
      )

  def with_status(query, "published"),
    do: from(q in query, where: q.status == 1)

  def with_status(query, status) when is_atom(status),
    do: with_status(query, to_string(status))

  def with_status(query, status), do: from(q in query, where: q.status == ^status)

  def with_language(query, languages) when is_list(languages),
    do: from(q in query, where: q.language in ^languages)

  def with_language(query, language), do: from(q in query, where: q.language == ^language)

  def with_exclude_language(query, languages) when is_list(languages),
    do: from(q in query, where: q.language not in ^languages)

  def with_exclude_language(query, language), do: from(q in query, where: q.language != ^language)

  def with_preload(query, preloads) do
    Enum.reduce(preloads, query, fn
      {key, {mod, pre}}, query ->
        from(t in query, preload: [{^key, ^from(p in mod, order_by: ^pre)}])

      {preload, :join}, query ->
        from(t in query, left_join: c in assoc(t, ^preload), preload: [{^preload, c}])

      {key, %{module: mod} = preload_map}, query ->
        preload_query = from(p in mod)

        preload_query =
          if pl = Map.get(preload_map, :preload) do
            from t in preload_query, preload: ^pl
          else
            preload_query
          end

        preload_query =
          if ob = Map.get(preload_map, :order) do
            from t in preload_query, order_by: ^ob
          else
            preload_query
          end

        preload_query =
          if Map.get(preload_map, :hide_deleted) do
            from t in preload_query, where: is_nil(t.deleted_at)
          else
            preload_query
          end

        from(t in query,
          preload: [{^key, ^preload_query}]
        )

      {key, preload_query}, query ->
        from(t in query, preload: [{^key, ^preload_query}])

      preload, query ->
        preload(query, ^preload)
    end)
  end

  @doc false
  defdelegate with_include(query, includes), to: Brando.Query.Include

  def with_join(query, joins) do
    Enum.reduce(joins, query, fn
      join, query ->
        from(t in query, left_join: c in assoc(t, ^join))
    end)
  end

  @doc """
  Hash query arguments
  """
  defdelegate hash_query(query_key), to: Cache.Query

  @doc """
  Check cache for query matching args
  """
  @spec try_cache(any(), any()) :: {:hit, any()} | {:miss, any(), any()} | :no_cache
  defdelegate try_cache(query_key, cache_opts), to: Cache.Query

  def run_list_query_reducer(context, args, initial_query, module) do
    prepared_args = prepare_args(args, module)
    includes = Map.get(prepared_args, :include)

    query =
      prepared_args
      |> Map.delete(:include)
      |> Enum.reduce(initial_query, fn
        {_, nil}, q -> q
        {:select, select}, q -> with_select(q, select)
        {:order, order}, q -> with_order(q, order)
        {:offset, offset}, q -> offset(q, ^offset)
        {:limit, 0}, q -> exclude(q, :limit)
        {:limit, limit}, q -> limit(q, ^limit)
        {:status, status}, q -> with_status(q, to_string(status))
        {:join, join}, q -> with_join(q, join)
        {:preload, preload}, q -> with_preload(q, preload)
        {:language, language}, q -> with_language(q, language)
        {:exclude_language, language}, q -> with_exclude_language(q, language)
        {:filter, filter}, q -> context.with_filter(q, module, filter)
        {:paginate, true}, q -> q
        {:with_deleted, true}, q -> q
        {:with_deleted, false}, q -> from query in q, where: is_nil(query.deleted_at)
        {:with_deleted, :only}, q -> from query in q, where: not is_nil(query.deleted_at)
      end)

    maybe_with_include(query, includes)
  end

  def run_single_query_reducer(context, args, module) do
    prepared_args = prepare_args(args, module)
    includes = Map.get(prepared_args, :include)

    query =
      prepared_args
      |> Map.delete(:include)
      |> Enum.reduce(module, fn
        {_, nil}, q -> q
        {:select, select}, q -> with_select(q, select)
        {:limit, limit}, q -> limit(q, ^limit)
        {:status, status}, q -> with_status(q, status)
        {:preload, preload}, q -> with_preload(q, preload)
        {:matches, match}, q -> context.with_match(q, module, match)
        {:revision, revision}, _ -> get_revision(module, args, revision)
        {:language, language}, q -> with_language(q, language)
        {:exclude_language, language}, q -> with_exclude_language(q, language)
        {:force_villain, _}, q -> q
        {:with_deleted, true}, q -> q
        {:with_deleted, false}, q -> from query in q, where: is_nil(query.deleted_at)
        {:with_deleted, :only}, q -> from query in q, where: not is_nil(query.deleted_at)
      end)

    maybe_with_include(query, includes)
  end

  defp maybe_with_include(query, nil), do: query
  defp maybe_with_include({status, _result} = result, _includes) when status in [:ok, :error], do: result
  defp maybe_with_include(query, includes), do: with_include(query, includes)

  defp prepare_args(%{revision: _} = args, _) do
    args
  end

  defp prepare_args(%{with_deleted: true} = args, _) do
    args
  end

  defp prepare_args(%{status: :deleted} = args, module) do
    if module.has_trait(Brando.Trait.SoftDelete) do
      Map.put(args, :with_deleted, :only)
    else
      args
    end
  end

  defp prepare_args(args, module) do
    if module.has_trait(Brando.Trait.SoftDelete) do
      Map.put(args, :with_deleted, false)
    else
      args
    end
  end

  defp get_revision(module, %{matches: %{id: id}}, revision) do
    case Revisions.get_revision(module, id, revision) do
      :error ->
        {:error, {:revision, :not_found}}

      {:ok, {_, {_, revisioned_entry}}} ->
        {:ok, revisioned_entry}
    end
  end

  # only build pagination_meta if offset & limit is set
  def maybe_build_pagination_meta(query, %{paginate: true, limit: 0}) do
    total_entries = get_total_entries(query)

    %{
      total_entries: total_entries,
      total_pages: 1,
      current_page: 1,
      previous_page: 1,
      next_page: 1,
      offset: 0,
      next_offset: 0,
      previous_offset: 0,
      page_size: 0
    }
  end

  def maybe_build_pagination_meta(query, %{paginate: true, limit: page_size} = list_opts) do
    total_entries = get_total_entries(query)
    total_pages = total_pages(total_entries, page_size)
    offset = Map.get(list_opts, :offset, 0)
    current_page = round(offset / page_size + 1)
    previous_page = get_previous_page(current_page)
    next_page = get_next_page(current_page, total_pages)

    %{
      total_entries: total_entries,
      total_pages: total_pages,
      current_page: current_page,
      previous_page: previous_page,
      next_page: next_page,
      offset: offset,
      next_offset: offset + page_size,
      previous_offset: max(offset - page_size, 0),
      page_size: page_size
    }
  end

  def maybe_build_pagination_meta(_, %{paginate: true}) do
    raise "==> QUERY: When `paginate` is true, you must supply `limit` args"
  end

  def maybe_build_pagination_meta(_, _), do: nil

  defp get_previous_page(1), do: 1
  defp get_previous_page(0), do: 1
  defp get_previous_page(page), do: page - 1

  defp get_next_page(page, total_pages) when page >= total_pages, do: total_pages
  defp get_next_page(page, _), do: page + 1

  defp get_total_entries(query) do
    total_entries =
      query
      |> exclude(:preload)
      |> exclude(:order_by)
      |> exclude(:limit)
      |> exclude(:offset)
      |> aggregate()
      |> Repo.one()

    total_entries || 0
  end

  defp aggregate(%{distinct: %{expr: expr}} = query) when expr == true or is_list(expr) do
    query
    |> exclude(:select)
    |> count()
  end

  defp aggregate(
         %{
           group_bys: [
             %Ecto.Query.QueryExpr{
               expr: [
                 {{:., [], [{:&, [], [source_index]}, field]}, [], []} | _
               ]
             }
             | _
           ]
         } = query
       ) do
    query
    |> exclude(:select)
    |> select([{x, source_index}], struct(x, ^[field]))
    |> count()
  end

  defp aggregate(query) do
    query
    |> exclude(:select)
    |> select(count("*"))
  end

  defp count(query) do
    query
    |> subquery
    |> select(count("*"))
  end

  defp total_pages(0, _), do: 1

  defp total_pages(total_entries, page_size) do
    (total_entries / page_size) |> Float.ceil() |> round
  end

  def insert(changeset, opts \\ []) do
    changeset
    |> Map.put(:action, :insert)
    |> Repo.insert(opts)
    |> Cache.Query.evict()
  end

  def update(changeset, opts \\ []) do
    changeset
    |> Map.put(:action, :update)
    |> Repo.update(opts)
    |> Cache.Query.evict()
  end

  def delete(entry) do
    entry
    |> Repo.delete()
    |> Cache.Query.evict()
  end

  @doc """
  Get entry with all possible preloads
  """
  defdelegate get_entry(schema, id), to: Brando.Blueprint.EntryQuery, as: :get

  @doc """
  Handle list queries
  """
  def handle_list_query(
        context,
        query_key,
        args,
        initial_query,
        module,
        stream \\ false
      ) do
    args = Brando.Authorization.Boundary.cache_options(args)
    initial_query = Brando.Authorization.Boundary.query(initial_query, module)
    cache_args = Map.get(args, :cache)

    case try_cache(query_key, cache_args) do
      {:miss, cache_key, ttl} ->
        query =
          run_list_query_reducer(
            context,
            Map.delete(args, :cache),
            initial_query,
            module
          )

        result = Repo.all(query)
        Brando.Cache.Query.put(cache_key, result, ttl)
        {:ok, result}

      {:hit, result} ->
        {:ok, result}

      :no_cache ->
        query =
          run_list_query_reducer(
            context,
            args,
            initial_query,
            module
          )

        pagination_meta = maybe_build_pagination_meta(query, args)

        if stream do
          Repo.stream(query)
        else
          entries = Repo.all(query)

          if pagination_meta do
            {:ok, %{entries: entries, pagination_meta: pagination_meta}}
          else
            {:ok, entries}
          end
        end
    end
  end

  @doc """
  Handle single queries
  """
  def handle_single_query(context, query_key, args, module, block, schema_atom) do
    args = Brando.Authorization.Boundary.cache_options(args)
    original_block = block
    block = fn query -> Brando.Authorization.Boundary.query(original_block.(query), module) end
    cache_args = Map.get(args, :cache)

    case try_cache(query_key, cache_args) do
      {:miss, cache_key, ttl} ->
        args_without_cache = Map.delete(args, :cache)
        includes = Map.get(args_without_cache, :include)

        reduced_query =
          run_single_query_reducer(
            context,
            Map.delete(args_without_cache, :include),
            module
          )

        case reduced_query do
          {:ok, entry} ->
            Brando.Cache.Query.put(cache_key, entry, ttl, entry.id)
            {:ok, entry}

          {:error, {:revision, :not_found}} ->
            {:error, {schema_atom, :not_found}}

          query ->
            query
            |> block.()
            |> with_include(includes)
            |> limit(1)
            |> Repo.one()
            |> case do
              nil ->
                {:error, {schema_atom, :not_found}}

              result ->
                Brando.Cache.Query.put(cache_key, result, ttl, result.id)
                {:ok, result}
            end
        end

      {:hit, result} ->
        {:ok, result}

      :no_cache ->
        args_without_cache = Map.delete(args, :cache)
        includes = Map.get(args_without_cache, :include)

        reduced_query =
          run_single_query_reducer(
            context,
            Map.delete(args_without_cache, :include),
            module
          )

        case reduced_query do
          {:ok, entry} ->
            {:ok, entry}

          {:error, {:revision, :not_found}} ->
            {:error, {schema_atom, :not_found}}

          query ->
            query
            |> block.()
            |> with_include(includes)
            |> limit(1)
            |> Repo.one()
            |> case do
              nil -> {:error, {schema_atom, :not_found}}
              result -> {:ok, result}
            end
        end
    end
  end

  def sanitize_ilike_pattern(text) when is_binary(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  def sanitize_ilike_pattern(text) when is_list(text) do
    Enum.map(text, &sanitize_ilike_pattern/1)
  end

  def sanitize_ilike_pattern(text) do
    text
  end
end

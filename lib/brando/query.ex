defmodule Brando.Query do
  @moduledoc """
  Query macros to DRY up contexts

  # Mutations

      ```
      mutation :create, Post
      mutation :update, Post
      mutation :delete, Post
      mutation :duplicate, {Post, change_fields: [:title], delete_fields: [:comments]}
      ```

  You can pass a function to execute after the mutation is finished:

      ```
      mutation :create, Post do
        fn entry ->
          {:ok, entry}
        end
      end
      ```

  You can pass preloads to the `:update` mutation:

      ```
      mutation :update, {Project, preload: [:tags]}
      ```

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


  # Preload

  ## Examples

  Preloads comments association:

      {:ok, results} = list_posts(%{preload: [:comments]})

  For simple ordering of the preload association, you can use
  a more complex setup of `{key, {schema, [direction: sort_key]}}`. For instance:

      {:ok, results} = list_posts(%{preload: [{:comments, {Comment, [desc: :inserted_at]}}]})

  You can also supply a preorder query directly:

      {:ok, results} = list_posts(%{preload: [{:comments, from(c in Comment, order_by: c.inserted_at)}]})


  # Cache

  ## Examples

      {:ok, results} = list_posts(%{status: :published, cache: true})
      {:ok, results} = list_posts(%{status: :published, cache: {:ttl, :timer.minutes(15)}})
  """

  import Ecto.Query

  alias Brando.Cache
  alias Brando.Revisions

  @default_callback {:fn, [], [{:->, [], [[{:entry, [], nil}], {:ok, {:entry, [], nil}}]}]}

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
    end
  end

  @doc """

  ## Usage

      query :list, Product do
        default fn
          query -> from q in query, where: is_nil(q.deleted_at)
        end
      end

      filters Product do
        fn
          {:title, title}, query -> from q in query, where: ilike(q.title, ^"%\#{title}%")
          {:name, name}, query -> from q in query, where: ilike(q.name, ^"%\#{name}%")
        end
      end
  """
  defmacro query(:list, module, do: block),
    do: query_list(Macro.expand(module, __CALLER__), block)

  defmacro query(:single, module, do: block),
    do: query_single(Macro.expand(module, __CALLER__), block)

  defmacro mutation(:create, module), do: mutation_create(Macro.expand(module, __CALLER__))

  defmacro mutation(:update, {module, opts}),
    do: mutation_update({Macro.expand(module, __CALLER__), opts})

  defmacro mutation(:update, module), do: mutation_update(Macro.expand(module, __CALLER__))
  defmacro mutation(:delete, module), do: mutation_delete(Macro.expand(module, __CALLER__))

  defmacro mutation(:duplicate, {module, opts}),
    do: mutation_duplicate({Macro.expand(module, __CALLER__), opts})

  defmacro mutation(:duplicate, module),
    do: mutation_duplicate(Macro.expand(module, __CALLER__))

  defmacro mutation(:create, module, do: callback_block),
    do: mutation_create(Macro.expand(module, __CALLER__), callback_block)

  defmacro mutation(:update, {module, opts}, do: callback_block),
    do: mutation_update({Macro.expand(module, __CALLER__), opts}, callback_block)

  defmacro mutation(:update, module, do: callback_block),
    do: mutation_update(Macro.expand(module, __CALLER__), callback_block)

  defmacro mutation(:delete, module, do: callback_block),
    do: mutation_delete(Macro.expand(module, __CALLER__), callback_block)

  defmacro filters(module, do: block), do: filter_query(module, block)
  defmacro matches(module, do: block), do: match_query(module, block)

  defmacro filters(do: _),
    do:
      raise("""

      filters/1 is deprecated.

      Specify Schema as argument:

          filters Post do
            ...
          end
      """)

  defp query_list(module, block) do
    source = module.__schema__(:source)

    pluralized_schema =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()
      |> Inflex.pluralize()

    quote do
      @spec unquote(:"list_#{pluralized_schema}")(map(), boolean) :: {:ok, list()}
      def unquote(:"list_#{pluralized_schema}")(args \\ %{}, stream \\ false) do
        initial_query = unquote(block).(unquote(module))
        cache_args = Map.get(args, :cache)

        case try_cache({:list, unquote(source), args}, cache_args) do
          {:miss, cache_key, ttl} ->
            query =
              run_list_query_reducer(
                __MODULE__,
                Map.delete(args, :cache),
                initial_query,
                unquote(module)
              )

            result = Brando.repo().all(query)
            Brando.Cache.Query.put(cache_key, result, ttl)
            {:ok, result}

          {:hit, result} ->
            {:ok, result}

          :no_cache ->
            query =
              run_list_query_reducer(
                __MODULE__,
                args,
                initial_query,
                unquote(module)
              )

            pagination_meta = maybe_build_pagination_meta(query, args)

            if stream do
              Brando.repo().stream(query)
            else
              entries = Brando.repo().all(query)

              if pagination_meta do
                {:ok, %{entries: entries, pagination_meta: pagination_meta}}
              else
                {:ok, entries}
              end
            end
        end
      end
    end
  end

  defp query_single(module, block) do
    source = module.__schema__(:source)

    singular_schema =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    singular_schema_atom = String.to_existing_atom(singular_schema)

    quote do
      @spec unquote(:"get_#{singular_schema}")(integer | binary | map()) ::
              {:ok, any} | {:error, {unquote(singular_schema_atom), :not_found}}
      def unquote(:"get_#{singular_schema}")(id) when is_binary(id) or is_integer(id) do
        query = unquote(block).(unquote(module)) |> where([t], t.id == ^id)

        case Brando.repo().one(query) do
          nil -> {:error, {unquote(singular_schema_atom), :not_found}}
          result -> {:ok, result}
        end
      end

      def unquote(:"get_#{singular_schema}")(args) when is_map(args) do
        cache_args = Map.get(args, :cache)

        case try_cache({:single, unquote(source), args}, cache_args) do
          {:miss, cache_key, ttl} ->
            args_without_cache = Map.delete(args, :cache)

            reduced_query =
              run_single_query_reducer(
                __MODULE__,
                args_without_cache,
                unquote(module)
              )

            case reduced_query do
              {:ok, entry} ->
                Brando.Cache.Query.put(cache_key, entry, ttl, entry.id)
                {:ok, entry}

              {:error, {:revision, :not_found}} ->
                {:error, {unquote(singular_schema_atom), :not_found}}

              query ->
                query
                |> unquote(block).()
                |> limit(1)
                |> Brando.repo().one()
                |> case do
                  nil ->
                    {:error, {unquote(singular_schema_atom), :not_found}}

                  result ->
                    Brando.Cache.Query.put(cache_key, result, ttl, result.id)
                    {:ok, result}
                end
            end

          {:hit, result} ->
            {:ok, result}

          :no_cache ->
            args_without_cache = Map.delete(args, :cache)

            reduced_query =
              run_single_query_reducer(
                __MODULE__,
                args_without_cache,
                unquote(module)
              )

            case reduced_query do
              {:ok, entry} ->
                {:ok, entry}

              {:error, {:revision, :not_found}} ->
                {:error, {unquote(singular_schema_atom), :not_found}}

              query ->
                query
                |> unquote(block).()
                |> limit(1)
                |> Brando.repo().one()
                |> case do
                  nil -> {:error, {unquote(singular_schema_atom), :not_found}}
                  result -> {:ok, result}
                end
            end
        end
      end

      @spec unquote(:"get_#{singular_schema}!")(integer | binary | map()) :: any | no_return
      def unquote(:"get_#{singular_schema}!")(id) when is_binary(id) or is_integer(id) do
        unquote(block).(unquote(module))
        |> where([t], t.id == ^id)
        |> Brando.repo().one!()
      end

      def unquote(:"get_#{singular_schema}!")(args) when is_map(args) do
        __MODULE__
        |> run_single_query_reducer(args, unquote(module))
        |> unquote(block).()
        |> limit(1)
        |> Brando.repo().one!()
      end
    end
  end

  defp filter_query(module, block) do
    quote do
      def with_filter(query, unquote(module), filter) do
        Enum.reduce(filter, query, unquote(block))
      end
    end
  end

  defp match_query(module, block) do
    quote do
      def with_match(query, unquote(module), match) do
        Enum.reduce(match, query, unquote(block))
        # rescue
        #   e in FunctionClauseError ->
        #     require Logger
        #     Logger.error(inspect(e, pretty: true))

        #     raise Brando.Exception.NoMatchingQueryMatchClause,
        #       message: """
        #       Could not find a matching query `matches` clause in `#{inspect(unquote(module))}
        #       """

        #   e ->
        #     reraise e, __STACKTRACE__
      end
    end
  end

  def with_order(query, order) when is_list(order) do
    Enum.reduce(order, query, fn
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

  def with_order(query, order), do: with_order(query, [order])
  def with_select(query, {:map, fields}), do: from(q in query, select: map(q, ^fields))
  def with_select(query, {:struct, fields}), do: from(q in query, select: ^fields)
  def with_select(query, fields), do: from(q in query, select: map(q, ^fields))
  def with_status(query, "all"), do: query

  def with_status(query, "deleted"),
    do: from(q in exclude(query, :where), where: not is_nil(q.deleted_at))

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

  def with_preload(query, preloads) do
    Enum.reduce(preloads, query, fn
      {key, {mod, pre}}, query ->
        from(t in query, preload: [{^key, ^from(p in mod, order_by: ^pre)}])

      {key, preload_query}, query ->
        from(t in query, preload: [{^key, ^preload_query}])

      preload, query ->
        preload(query, ^preload)
    end)
  end

  @doc """
  Hash query arguments
  """
  def hash_query({query_type, query_name, _} = query_key) do
    {query_type, query_name,
     Base.encode16(<<:erlang.phash2(Jason.encode!(query_key))::size(32)>>)}
  end

  @doc """
  Check cache for query matching args
  """
  @spec try_cache(any(), any()) :: any()
  def try_cache(query_key, cache_opts)
  def try_cache(_query_key, nil), do: :no_cache
  def try_cache(_query_key, false), do: :no_cache

  def try_cache(query_key, true), do: try_cache(query_key, {:ttl, :timer.minutes(15)})

  def try_cache(query_key, {:ttl, ttl}) do
    cache_key = hash_query(query_key)

    case Cache.Query.get(cache_key) do
      nil -> {:miss, cache_key, ttl}
      result -> {:hit, result}
    end
  end

  def run_list_query_reducer(context, args, initial_query, module) do
    Enum.reduce(args, initial_query, fn
      {_, nil}, q -> q
      {:select, select}, q -> with_select(q, select)
      {:order, order}, q -> with_order(q, order)
      {:offset, offset}, q -> offset(q, ^offset)
      {:limit, limit}, q -> limit(q, ^limit)
      {:status, status}, q -> with_status(q, to_string(status))
      {:preload, preload}, q -> with_preload(q, preload)
      {:filter, filter}, q -> context.with_filter(q, module, filter)
      {:paginate, true}, q -> q
    end)
  end

  def run_single_query_reducer(context, args, module) do
    Enum.reduce(args, module, fn
      {_, nil}, q -> q
      {:limit, limit}, q -> limit(q, ^limit)
      {:status, status}, q -> with_status(q, status)
      {:preload, preload}, q -> with_preload(q, preload)
      {:matches, match}, q -> context.with_match(q, module, match)
      {:revision, revision}, _ -> get_revision(module, args, revision)
    end)
  end

  defp get_revision(module, %{matches: %{id: id}}, revision) do
    case Revisions.get_revision(module, id, revision) do
      :error ->
        {:error, {:revision, :not_found}}

      {:ok, {_, {_, revisioned_entry}}} ->
        {:ok, revisioned_entry}
    end
  end

  defp mutation_create(module, callback_block \\ nil) do
    singular_schema =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    callback_block = callback_block || @default_callback

    quote generated: true do
      @spec unquote(:"create_#{singular_schema}")(map, Brando.Users.User.t() | :system) ::
              {:ok, any} | {:error, Ecto.Changeset.t()}
      def unquote(:"create_#{singular_schema}")(params, user, opts \\ [])

      def unquote(:"create_#{singular_schema}")(%Ecto.Changeset{} = changeset, user, _) do
        Brando.Query.Mutations.create_with_changeset(
          unquote(module),
          changeset,
          user,
          unquote(callback_block)
        )
      end

      def unquote(:"create_#{singular_schema}")(params, user, opts) do
        Brando.Query.Mutations.create(
          unquote(module),
          params,
          user,
          unquote(callback_block),
          Keyword.get(opts, :changeset, nil)
        )
      end
    end
  end

  defp mutation_update(module, callback_block \\ nil)

  defp mutation_update({module, opts}, callback_block) do
    singular_schema =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    callback_block = callback_block || @default_callback

    do_mutation_update(module, singular_schema, callback_block, opts)
  end

  defp mutation_update(module, callback_block) do
    singular_schema =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    callback_block = callback_block || @default_callback

    do_mutation_update(module, singular_schema, callback_block)
  end

  defp do_mutation_update(module, singular_schema, callback_block, opts \\ []) do
    preloads = Keyword.get(opts, :preload)

    quote do
      @spec unquote(:"update_#{singular_schema}")(
              integer | binary,
              map,
              Brando.Users.User.t() | :system
            ) ::
              {:ok, any} | {:error, Ecto.Changeset.t()}
      def unquote(:"update_#{singular_schema}")(schema, params, user, opts \\ [])

      def unquote(:"update_#{singular_schema}")(%{id: id}, params, user, opts) do
        Brando.Query.Mutations.update(
          __MODULE__,
          unquote(module),
          unquote(singular_schema),
          id,
          params,
          user,
          unquote(preloads),
          unquote(callback_block),
          Keyword.get(opts, :changeset, nil)
        )
      end

      def unquote(:"update_#{singular_schema}")(id, params, user, opts) do
        Brando.Query.Mutations.update(
          __MODULE__,
          unquote(module),
          unquote(singular_schema),
          id,
          params,
          user,
          unquote(preloads),
          unquote(callback_block),
          Keyword.get(opts, :changeset, nil)
        )
      end

      def unquote(:"update_#{singular_schema}")(%Ecto.Changeset{} = changeset, user) do
        Brando.Query.Mutations.update_with_changeset(
          unquote(module),
          changeset,
          user,
          unquote(callback_block)
        )
      end
    end
  end

  defp mutation_duplicate({module, opts}), do: do_mutation_duplicate(module, opts)
  defp mutation_duplicate(module), do: do_mutation_duplicate(module, [])

  defp do_mutation_duplicate(module, opts) do
    singular_schema =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    quote do
      @spec unquote(:"duplicate_#{singular_schema}")(
              integer | binary,
              Brando.Users.User.t() | :system
            ) ::
              {:ok, any} | {:error, Ecto.Changeset.t()}
      def unquote(:"duplicate_#{singular_schema}")(id, user) do
        Brando.Query.Mutations.duplicate(
          __MODULE__,
          unquote(module),
          unquote(singular_schema),
          id,
          unquote(opts),
          user
        )
      end
    end
  end

  defp mutation_delete(module, callback_block \\ nil) do
    singular_schema =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    callback_block = callback_block || @default_callback

    quote do
      @spec unquote(:"delete_#{singular_schema}")(integer | binary) ::
              {:ok, any} | {:error, Ecto.Changeset.t()}
      def unquote(:"delete_#{singular_schema}")(id, user \\ :system) do
        Brando.Query.Mutations.delete(
          __MODULE__,
          unquote(module),
          unquote(singular_schema),
          id,
          user,
          unquote(callback_block)
        )
      end
    end
  end

  # only build pagination_meta if offset & limit is set
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
      |> Brando.repo().one()

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
    |> Brando.repo().insert(opts)
    |> Cache.Query.evict()
  end

  def update(changeset, opts \\ []) do
    changeset
    |> Map.put(:action, :update)
    |> Brando.repo().update(opts)
    |> Cache.Query.evict()
  end

  def delete(entry) do
    entry
    |> Brando.repo().delete()
    |> Cache.Query.evict()
  end
end

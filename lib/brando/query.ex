defmodule Brando.Query do
  @moduledoc """
  Query macros to DRY up contexts

  # Mutations

  ```
      mutation :create, Post
      mutation :update, Post
      mutation :delete, Post
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

  @default_after_operation {:fn, [], [{:->, [], [[{:entry, [], nil}], {:ok, {:entry, [], nil}}]}]}

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

  defmacro mutation(:create, module, do: block),
    do: mutation_create(Macro.expand(module, __CALLER__), block)

  defmacro mutation(:update, {module, opts}, do: block),
    do: mutation_update({Macro.expand(module, __CALLER__), opts}, block)

  defmacro mutation(:update, module, do: block),
    do: mutation_update(Macro.expand(module, __CALLER__), block)

  defmacro mutation(:delete, module, do: block),
    do: mutation_delete(Macro.expand(module, __CALLER__), block)

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
    # check for publish_at field
    publish_at? = Map.has_key?(module.__struct__, :publish_at)
    source = module.__schema__(:source)

    name =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()
      |> Inflex.pluralize()

    quote do
      @spec unquote(:"list_#{name}")(map(), boolean) :: {:ok, any}
      def unquote(:"list_#{name}")(args \\ %{}, stream \\ false) do
        initial_query = unquote(block).(unquote(module))
        cache_args = Map.get(args, :cache)

        case try_cache({:list, unquote(source), args}, cache_args) do
          {:miss, cache_key, ttl} ->
            query =
              run_list_query_reducer(
                __MODULE__,
                Map.delete(args, :cache),
                initial_query,
                unquote(module),
                unquote(publish_at?)
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
                unquote(module),
                unquote(publish_at?)
              )

            if stream do
              Brando.repo().stream(query)
            else
              {:ok, Brando.repo().all(query)}
            end
        end
      end
    end
  end

  defp query_single(module, block) do
    # check for publish_at field
    publish_at? = Map.has_key?(module.__struct__, :publish_at)
    source = module.__schema__(:source)

    name =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    atom = String.to_existing_atom(name)

    quote do
      @spec unquote(:"get_#{name}")(integer | binary | map()) ::
              {:ok, any} | {:error, {unquote(atom), :not_found}}
      def unquote(:"get_#{name}")(id) when is_binary(id) or is_integer(id) do
        query = unquote(block).(unquote(module)) |> where([t], t.id == ^id)

        case Brando.repo().one(query) do
          nil -> {:error, {unquote(atom), :not_found}}
          result -> {:ok, result}
        end
      end

      def unquote(:"get_#{name}")(args) when is_map(args) do
        cache_args = Map.get(args, :cache)

        case try_cache({:single, unquote(source), args}, cache_args) do
          {:miss, cache_key, ttl} ->
            __MODULE__
            |> run_single_query_reducer(
              Map.delete(args, :cache),
              unquote(module),
              unquote(publish_at?)
            )
            |> unquote(block).()
            |> limit(1)
            |> Brando.repo().one()
            |> case do
              nil ->
                {:error, {unquote(atom), :not_found}}

              result ->
                Brando.Cache.Query.put(cache_key, result, ttl, result.id)
                {:ok, result}
            end

          {:hit, result} ->
            {:ok, result}

          :no_cache ->
            result =
              __MODULE__
              |> run_single_query_reducer(
                Map.delete(args, :cache),
                unquote(module),
                unquote(publish_at?)
              )
              |> unquote(block).()
              |> limit(1)
              |> Brando.repo().one()
              |> case do
                nil -> {:error, {unquote(atom), :not_found}}
                result -> {:ok, result}
              end
        end
      end

      @spec unquote(:"get_#{name}!")(integer | binary | map()) :: any | no_return
      def unquote(:"get_#{name}!")(id) when is_binary(id) or is_integer(id) do
        unquote(block).(unquote(module))
        |> where([t], t.id == ^id)
        |> Brando.repo().one!()
      end

      def unquote(:"get_#{name}!")(args) when is_map(args) do
        __MODULE__
        |> run_single_query_reducer(args, unquote(module), unquote(publish_at?))
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
  def with_status(query, "all", _), do: query

  def with_status(query, "deleted", _),
    do: from(q in exclude(query, :where), where: not is_nil(q.deleted_at))

  def with_status(query, "published_all", true),
    do:
      from(q in query,
        where: q.status == 1
      )

  def with_status(query, "published", true),
    do:
      from(q in query,
        where: q.status == 1,
        where:
          is_nil(q.publish_at) or
            fragment("?::timestamp", q.publish_at) < ^NaiveDateTime.utc_now()
      )

  def with_status(query, "published", false),
    do: from(q in query, where: q.status == 1)

  def with_status(query, status, publish_at?) when is_atom(status),
    do: with_status(query, to_string(status), publish_at?)

  def with_status(query, status, _), do: from(q in query, where: q.status == ^status)

  def with_preload(query, preloads) do
    Enum.reduce(preloads, query, fn
      {key, {mod, pre}}, query ->
        from t in query, preload: [{^key, ^from(p in mod, order_by: ^pre)}]

      {key, preload_query}, query ->
        from t in query, preload: [{^key, ^preload_query}]

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

    case Brando.Cache.Query.get(cache_key) do
      nil -> {:miss, cache_key, ttl}
      result -> {:hit, result}
    end
  end

  def run_list_query_reducer(context, args, initial_query, module, publish_at?) do
    Enum.reduce(args, initial_query, fn
      {_, nil}, q -> q
      {:select, select}, q -> with_select(q, select)
      {:order, order}, q -> with_order(q, order)
      {:offset, offset}, q -> offset(q, ^offset)
      {:limit, limit}, q -> limit(q, ^limit)
      {:status, status}, q -> with_status(q, to_string(status), publish_at?)
      {:preload, preload}, q -> with_preload(q, preload)
      {:filter, filter}, q -> context.with_filter(q, module, filter)
    end)
  end

  def run_single_query_reducer(context, args, module, publish_at?) do
    Enum.reduce(args, module, fn
      {_, nil}, q -> q
      {:limit, limit}, q -> limit(q, ^limit)
      {:status, status}, q -> with_status(q, status, publish_at?)
      {:preload, preload}, q -> with_preload(q, preload)
      {:matches, match}, q -> context.with_match(q, module, match)
    end)
  end

  defp mutation_create(module, block \\ nil) do
    name =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    block = block || @default_after_operation

    quote generated: true do
      @spec unquote(:"create_#{name}")(map, Brando.Users.User.t() | :system) ::
              {:ok, any} | {:error, Ecto.Changeset.t()}
      def unquote(:"create_#{name}")(params, user \\ :system) do
        with changeset <- unquote(module).changeset(%unquote(module){}, params, user),
             {:ok, entry} <- Brando.Query.insert(changeset) do
          Brando.Datasource.update_datasource(unquote(module), entry)
          unquote(block).(entry)
        else
          err -> err
        end
      end
    end
  end

  defp mutation_update(module, block \\ nil)

  defp mutation_update({module, opts}, block) do
    name =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    block = block || @default_after_operation

    do_mutation_update(module, name, block, opts)
  end

  defp mutation_update(module, block) do
    name =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    block = block || @default_after_operation

    do_mutation_update(module, name, block)
  end

  defp do_mutation_update(module, name, block, opts \\ []) do
    preloads = Keyword.get(opts, :preload)

    quote do
      @spec unquote(:"update_#{name}")(integer | binary, map, Brando.Users.User.t() | :system) ::
              {:ok, any} | {:error, Ecto.Changeset.t()}
      def unquote(:"update_#{name}")(id, params, user \\ :system) do
        get_opts =
          if unquote(preloads) do
            %{matches: %{id: id}, preload: unquote(preloads)}
          else
            %{matches: %{id: id}}
          end

        with {:ok, entry} <- unquote(:"get_#{name}")(get_opts),
             changeset <- unquote(module).changeset(entry, params, user),
             {:ok, entry} <- Brando.Query.update(changeset) do
          Brando.Datasource.update_datasource(unquote(module), entry)
          unquote(block).(entry)
        else
          err -> err
        end
      end
    end
  end

  defp mutation_delete(module, block \\ nil) do
    name =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    block = block || @default_after_operation

    quote do
      @spec unquote(:"delete_#{name}")(integer | binary) ::
              {:ok, any} | {:error, Ecto.Changeset.t()}
      def unquote(:"delete_#{name}")(id) do
        {:ok, entry} = unquote(:"get_#{name}")(id)

        if {:__soft_delete__, 0} in unquote(module).__info__(:functions) do
          Brando.repo().soft_delete(entry)
        else
          Brando.Query.delete(entry)
        end

        if {:__gallery_fields__, 0} in unquote(module).__info__(:functions) do
          for f <- apply(unquote(module), :__gallery_fields__, []) do
            image_series_id = "#{to_string(f)}_id" |> String.to_existing_atom()
            Brando.Images.delete_series(Map.get(entry, image_series_id))
          end
        end

        Brando.Datasource.update_datasource(unquote(module), entry)
        unquote(block).(entry)
      end
    end
  end

  def insert(changeset) do
    changeset
    |> Brando.repo().insert()
    |> Brando.Cache.Query.evict()
  end

  def update(changeset) do
    changeset
    |> Brando.repo().update()
    |> Brando.Cache.Query.evict()
  end

  def delete(entry) do
    entry
    |> Brando.repo().delete()
    |> Brando.Cache.Query.evict()
  end
end

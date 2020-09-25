defmodule Brando.Query do
  @moduledoc """
  Query macros to DRY up contexts

  # Select

  ## Examples

      {:ok, posts} = list_posts(%{select: [:slug, :updated_at]})

  Default format, returns a map with `:slug` and `updated_at` keys.

      {:ok, posts} = list_posts(%{select: {:struct, [:slug, :updated_at]}})

  Returns a struct with `:slug` and `updated_at` keys.

      {:ok, posts} = list_posts(%{select: {:map, [:slug, :updated_at]}})

  Same as the default format, only explicitly marked parameters.


  # Preload

  ## Examples

  Preloads comments association:

      {:ok, results} = list_posts(%{preload: [:comments]})

  For simple ordering of the preload association, you can use
  a more complex setup of `{key, {schema, [direction: sort_key]}}`. For instance:

      {:ok, results} = list_posts(%{preload: [{:comments, {Comment, [desc: :inserted_at]}}]})

  You can also supply a preorder query directly:

      {:ok, results} = list_posts(%{preload: [{:comments, from(c in Comment, order_by: c.inserted_at)}]})

  """

  defmacro __using__(_) do
    quote do
      import Ecto.Query
      import unquote(__MODULE__)

      defp with_order(query, order) when is_list(order) do
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

          {dir, by}, query ->
            query |> order_by({^dir, ^by})
        end)
      end

      defp with_order(query, order), do: with_order(query, [order])
      defp with_select(query, {:map, fields}), do: from(q in query, select: map(q, ^fields))
      defp with_select(query, {:struct, fields}), do: from(q in query, select: ^fields)
      defp with_select(query, fields), do: from(q in query, select: map(q, ^fields))
      defp with_status(query, "all", _), do: query

      defp with_status(query, "deleted", _),
        do: from(q in exclude(query, :where), where: not is_nil(q.deleted_at))

      defp with_status(query, "published_all", true),
        do:
          from(q in query,
            where: q.status == 1
          )

      defp with_status(query, "published", true),
        do:
          from(q in query,
            where: q.status == 1,
            where:
              is_nil(q.publish_at) or
                fragment("?::timestamp", q.publish_at) < ^NaiveDateTime.utc_now()
          )

      defp with_status(query, "published", false),
        do: from(q in query, where: q.status == 1)

      defp with_status(query, status, publish_at?) when is_atom(status),
        do: with_status(query, to_string(status), publish_at?)

      defp with_status(query, status, _), do: from(q in query, where: q.status == ^status)

      @doc """
      Preloads

      ## Examples

      Preloads comments association:

          {:ok, results} = list_posts(%{preload: [:comments]})

      For simple ordering of the preload association, you can use
      a more complex setup of `{key, {schema, [direction: sort_key]}}`. For instance:

          {:ok, results} = list_posts(%{preload: [{:comments, {Comment, [desc: :inserted_at]}}]})

      You can also supply a preorder query directly:

          {:ok, results} = list_posts(%{preload: [{:comments, from(c in Comment, order_by: c.inserted_at)}]})

      """
      def with_preload(query, preloads) do
        Enum.reduce(preloads, query, fn
          {key, {mod, pre}}, query ->
            from t in query, preload: [{^key, ^from(p in mod, order_by: ^pre)}]

          {key, preload_query}, query ->
            from t in query, preload: [{^key, ^preload_query}]

          preload, query ->
            query |> preload(^preload)
        end)
      end
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

    name =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()
      |> Inflex.pluralize()

    quote do
      def unquote(:"list_#{name}")(args \\ %{}, stream \\ false) do
        initial_query = unquote(block).(unquote(module))

        query =
          args
          |> Enum.reduce(initial_query, fn
            {_, nil}, query ->
              query

            {:select, select}, query ->
              query |> with_select(select)

            {:order, order}, query ->
              query |> with_order(order)

            {:offset, offset}, query ->
              query |> offset(^offset)

            {:limit, limit}, query ->
              query |> limit(^limit)

            {:status, status}, query ->
              query |> with_status(to_string(status), unquote(publish_at?))

            {:preload, preload}, query ->
              query |> with_preload(preload)

            {:filter, filter}, query ->
              query |> with_filter(unquote(module), filter)
          end)

        if stream do
          Brando.repo().stream(query)
        else
          {:ok, Brando.repo().all(query)}
        end
      end
    end
  end

  defp query_single(module, block) do
    # check for publish_at field
    publish_at? = Map.has_key?(module.__struct__, :publish_at)

    name =
      module
      |> Module.split()
      |> List.last()
      |> Inflex.underscore()

    atom = String.to_existing_atom(name)

    quote do
      def unquote(:"get_#{name}")(id) when is_binary(id) or is_integer(id) do
        query = unquote(block).(unquote(module)) |> where([t], t.id == ^id)

        case Brando.repo().one(query) do
          nil -> {:error, {unquote(atom), :not_found}}
          result -> {:ok, result}
        end
      end

      def unquote(:"get_#{name}")(args) when is_map(args) do
        query =
          args
          |> Enum.reduce(unquote(module), fn
            {_, nil}, query ->
              query

            {:limit, limit}, query ->
              query |> limit(^limit)

            {:status, status}, query ->
              query |> with_status(status, unquote(publish_at?))

            {:preload, preload}, query ->
              query |> with_preload(preload)

            {:matches, match}, query ->
              query |> with_match(unquote(module), match)
          end)

        query = unquote(block).(query) |> limit(1)

        case Brando.repo().one(query) do
          nil -> {:error, {unquote(atom), :not_found}}
          result -> {:ok, result}
        end
      end
    end
  end

  defp filter_query(module, block) do
    quote do
      defp with_filter(query, unquote(module), filter) do
        Enum.reduce(filter, query, unquote(block))
      end
    end
  end

  defp match_query(module, block) do
    quote do
      defp with_match(query, unquote(module), match) do
        Enum.reduce(match, query, unquote(block))
      end
    end
  end
end

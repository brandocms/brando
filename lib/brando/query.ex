defmodule Brando.Query do
  @moduledoc """
  Query macros to DRY up contexts

  # Preloads

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

          {dir, by}, query ->
            query |> order_by({^dir, ^by})
        end)
      end

      defp with_order(query, order), do: with_order(query, [order])

      defp with_status(query, "all"), do: query
      defp with_status(query, status), do: from(q in query, where: q.status == ^status)

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
  defmacro query(:list, module, do: block), do: query_list(module, block)
  defmacro filters(module, do: block), do: filter_query(module, block)

  defmacro filters(do: _),
    do:
      raise("""

      filters/1 is deprecated.

      Specify Schema as argument:

          filters Post do
            ...
          end
      """)

  defp query_list({_, _, module_list} = module, block) do
    name =
      module_list
      |> List.last()
      |> to_string()
      |> String.downcase()
      |> Inflex.pluralize()

    quote do
      def unquote(:"list_#{name}")(args \\ %{}) do
        query =
          args
          |> Enum.reduce(unquote(module), fn
            {_, nil}, query ->
              query

            {:order, order}, query ->
              query |> with_order(order)

            {:offset, offset}, query ->
              query |> offset(^offset)

            {:limit, limit}, query ->
              query |> limit(^limit)

            {:status, status}, query ->
              query |> with_status(status)

            {:preload, preload}, query ->
              query |> with_preload(preload)

            {:filter, filter}, query ->
              query |> with_filter(unquote(module), filter)
          end)

        query = unquote(block).(query)

        {:ok, Brando.repo().all(query)}
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
end

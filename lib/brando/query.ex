defmodule Brando.Query do
  @moduledoc """
  Query macros to DRY up contexts
  """

  defmacro __using__(_) do
    quote do
      import Ecto.Query
      import unquote(__MODULE__)
    end
  end

  @doc """

  ## Usage

      query :list, :products do
        default fn
          query -> from q in query, where: is_nil(q.deleted_at)
        end
      end

      filters do
        fn
          {:title, title}, query -> from q in query, where: ilike(q.title, ^"%\#{title}%")
          {:name, name}, query -> from q in query, where: ilike(q.name, ^"%\#{name}%")
        end
      end
  """
  defmacro query(:list, module, do: block), do: query_list(module, block)
  defmacro filters(do: block), do: filter_query(block)

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

            {:filter, filter}, query ->
              query |> with_filter(filter)
          end)

        query = unquote(block).(query)

        {:ok, Brando.repo().all(query)}
      end

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
    end
  end

  defp filter_query(block) do
    quote do
      defp with_filter(query, filter) do
        Enum.reduce(filter, query, unquote(block))
      end
    end
  end
end

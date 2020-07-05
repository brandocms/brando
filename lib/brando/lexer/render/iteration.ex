defmodule Brando.Lexer.Render.Iteration do
  @moduledoc false

  alias Brando.Lexer.Argument
  alias Brando.Lexer.Context

  @behaviour Brando.Lexer.Render

  @impl Brando.Lexer.Render
  @spec render(any, Context.t()) :: {iolist, Context.t()}
  def render({:iteration, tag}, context), do: do_render(tag, context)
  def render(_, _), do: false

  defp do_render([for: for_statement], %Context{} = context),
    do: do_render([for: for_statement, else: [contents: []]], context)

  defp do_render(
         [
           for: [
             identifier: identifier,
             collection: collection,
             parameters: parameters,
             contents: contents
           ],
           else: [contents: else_contents]
         ],
         %Context{} = context
       ) do
    collection
    |> Argument.eval(context)
    |> eval_modifiers(parameters)
    |> render_collection(identifier, contents, else_contents, context)
  end

  defp do_render([tag], context) when tag in [:break, :continue],
    do: throw({tag, context})

  defp do_render(_, _), do: false

  defp eval_modifiers(collection, []), do: collection

  defp eval_modifiers(collection, [{:limit, limit} | tail]),
    do: collection |> Enum.take(limit) |> eval_modifiers(tail)

  defp eval_modifiers(collection, [{:offset, offset} | tail]),
    do: collection |> Enum.drop(offset) |> eval_modifiers(tail)

  defp eval_modifiers(collection, [{:order, :reversed} | tail]),
    do: collection |> Enum.reverse() |> eval_modifiers(tail)

  defp render_collection([], _, _, contents, context),
    do: Brando.Lexer.render(contents, context)

  defp render_collection(results, identifier, contents, _, context) do
    forloop_init = Map.get(context.variables, "forloop")
    len = Enum.count(results)

    {result, context} =
      results
      |> Enum.with_index(0)
      |> Enum.reduce({[], context}, fn {record, index}, {acc, ctx} ->
        try do
          # Assign the loop variables
          ctx =
            ctx
            |> Context.assign("forloop", forloop(index, len))
            |> Context.assign(identifier, record)

          {r, ctx} = Brando.Lexer.render(contents, ctx)

          {
            [r | acc],
            Context.assign(ctx, "forloop", forloop_init)
          }
        catch
          {:continue, ctx} ->
            {acc, Context.assign(ctx, "forloop", forloop_init)}

          {:break, ctx} ->
            throw({:result, acc, Context.assign(ctx, "forloop", forloop_init)})
        end
      end)

    {Enum.reverse(result), context}
  catch
    {:result, result, context} ->
      # credo:disable-for-next-line
      {Enum.reverse(result), context}
  end

  defp forloop(index, count) do
    %{
      "index" => index + 1,
      "index0" => index,
      "rindex" => count - index,
      "rindex0" => count - index - 1,
      "first" => index == 0,
      "last" => index == count - 1,
      "count" => count
    }
  end
end

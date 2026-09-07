if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.RouteInventory do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Function, as: CodeFunction
    alias Sourceror.Zipper

    @verbs [:get, :post, :put, :patch, :delete, :options, :head, :live, :match]

    def insert_before_routes(zipper, code) do
      case Common.move_to(zipper, &route_call?/1) do
        {:ok, route} -> {:ok, Common.add_code(route, code, placement: :before)}
        :error -> {:ok, Common.add_code(zipper, code)}
      end
    end

    defp route_call?(call) do
      Enum.any?([:scope, :get, :match, :forward, :resources, :page_routes, :admin_routes], fn name ->
        CodeFunction.function_call?(call, name, :any)
      end)
    end

    # Read source declarations without expanding consumer macros or loading its router.
    # Unknown dynamic paths require explicit integration instead of guessing ownership.
    def read(zipper) do
      collect(quoted(zipper), "", nil)
    end

    def at(zipper) do
      {prefix, namespace} =
        zipper
        |> Zipper.up()
        |> scopes([])
        |> Enum.reduce({"", nil}, fn {:scope, _, [path | rest]}, {prefix, namespace} ->
          nested = Enum.find(rest, &match?({:__aliases__, _, _}, &1))
          {join(prefix, path), if(nested, do: module(nested, namespace), else: namespace)}
        end)

      collect(quoted(zipper), prefix, namespace)
    end

    defp scopes(nil, found), do: found

    defp scopes(zipper, found) do
      found =
        if CodeFunction.function_call?(zipper, :scope, [2, 3, 4]) do
          case quoted(zipper) do
            {:scope, _, [path | _]} = scope when is_binary(path) -> [scope | found]
            _ -> found
          end
        else
          found
        end

      scopes(Zipper.up(zipper), found)
    end

    defp quoted(zipper), do: zipper.node |> Sourceror.to_string() |> Code.string_to_quoted!()

    def same_path?(left, right), do: normalize(left) == normalize(right)

    def covers?(%{path: path, kind: kind}, requested) do
      cond do
        kind == :unknown -> true
        kind in [:resources, :forward, :admin_routes] -> requested == path || String.starts_with?(requested, path <> "/")
        String.contains?(path, "*") -> String.starts_with?(requested, path |> String.split("*") |> hd())
        true -> same_path?(path, requested)
      end
    end

    defp collect({:scope, _, [path | rest]}, prefix, namespace) when is_binary(path) do
      nested = Enum.find(rest, &match?({:__aliases__, _, _}, &1))
      namespace = if nested, do: module(nested, namespace), else: namespace
      collect(rest, join(prefix, path), namespace)
    end

    defp collect({:scope, _, _}, _prefix, _namespace), do: [unknown()]

    defp collect({kind, _, [path, destination | rest]}, prefix, namespace) when kind in @verbs and is_binary(path) do
      [%{kind: kind, path: join(prefix, path), module: module(destination, namespace), action: List.first(rest)}]
    end

    defp collect({kind, _, [path | _]}, prefix, _namespace)
         when kind in [:resources, :forward, :admin_routes] and is_binary(path) do
      [%{kind: kind, path: join(prefix, path), module: nil, action: nil}]
    end

    defp collect({:admin_routes, _, _}, prefix, _namespace),
      do: [%{kind: :admin_routes, path: join(prefix, "/admin"), module: nil, action: nil}]

    defp collect({:page_routes, _, _}, prefix, _namespace),
      do: [%{kind: :get, path: join(prefix, "/*path"), module: nil, action: nil}]

    defp collect({kind, _, _}, _prefix, _namespace) when kind in @verbs or kind in [:resources, :forward],
      do: [unknown()]

    defp collect({_, _, args}, prefix, namespace) when is_list(args), do: collect(args, prefix, namespace)
    defp collect({:do, body}, prefix, namespace), do: collect(body, prefix, namespace)
    defp collect(nodes, prefix, namespace) when is_list(nodes), do: Enum.flat_map(nodes, &collect(&1, prefix, namespace))
    defp collect(_, _, _), do: []

    defp module({:__aliases__, _, [:"Elixir" | parts]}, _namespace), do: Module.concat(parts)
    defp module({:__aliases__, _, parts}, nil), do: Module.concat(parts)
    defp module({:__aliases__, _, parts}, namespace), do: Module.concat([namespace | parts])
    defp module(_, _), do: nil
    defp unknown, do: %{kind: :unknown, path: "", module: nil, action: nil}
    defp normalize(path), do: Regex.replace(~r/:[^\/]+/, String.trim_trailing(path, "/"), ":param")
    defp join(prefix, path), do: "/" <> String.trim(prefix <> "/" <> String.trim_leading(path, "/"), "/")
  end
else
  defmodule Mix.Brando.Igniter.RouteInventory do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end

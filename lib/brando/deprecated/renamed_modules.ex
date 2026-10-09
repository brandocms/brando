defmodule Brando.Deprecated.RenamedModules do
  @moduledoc false
  # Public modules renamed in 0.55 (#2833). Each old name is a deprecated
  # shim in `lib/brando/deprecated/` until it is removed in 0.57:
  # `mix brando.migrate55` rewrites references to the old names, and
  # `mix brando.doctor` lists the ones left in an application's `lib/`.
  #
  # Module atoms only, so nothing here depends on the modules at compile time.

  alias Brando.Deprecated.LexicalAliases

  require Logger

  @removed_in "0.57"

  @renamed %{
    Brando.Config => Brando.Sites.Config,
    Brando.ErrorHTML => BrandoWeb.ErrorHTML,
    Brando.Link => Brando.Sites.Link,
    Brando.LivePreviewChannel => BrandoAdmin.LivePreviewChannel,
    Brando.LobbyChannel => BrandoAdmin.LobbyChannel,
    Brando.Meta => Brando.Sites.Meta,
    Brando.PreviewController => BrandoWeb.PreviewController,
    Brando.SEOController => BrandoWeb.SEOController,
    Brando.SitemapController => BrandoWeb.SitemapController,
    Brando.Upload => Brando.Uploads.Store,
    Brando.UserChannel => BrandoAdmin.UserChannel
  }

  @doc "Old module => new module."
  def all, do: @renamed

  @doc "The module `old` was renamed to, or nil."
  def new_name(old), do: Map.get(@renamed, old)

  def removed_in, do: @removed_in

  @doc """
  The segments under `old` of Brando's modules that kept their names:
  `["HTML"]` for `Brando.Meta`, whose `Brando.Meta.HTML` did not move.
  """
  def unmoved_children(old) do
    prefix = inspect(old) <> "."

    for module <- Application.spec(:brando, :modules) || [],
        name = inspect(module),
        String.starts_with?(name, prefix),
        not Map.has_key?(@renamed, module),
        uniq: true,
        do: name |> String.replace_prefix(prefix, "") |> String.split(".") |> hd()
  end

  @doc "Why `old` is deprecated, as the doctor and the shims' warnings say it."
  def reason(old) do
    "renamed to #{inspect(Map.fetch!(@renamed, old))}; the old name is removed in Brando #{@removed_in}. " <>
      "mix brando.migrate55 updates references"
  end

  @doc """
  Logs once per node that `old` was used. For the names a router, socket or
  endpoint config holds, which are looked up at runtime and so never see a
  compile-time `@deprecated` warning.
  """
  def warn(old) do
    key = {__MODULE__, old}

    unless :persistent_term.get(key, false) do
      :persistent_term.put(key, true)
      Logger.warning("#{inspect(old)} is deprecated: #{reason(old)}.")
    end

    :ok
  end

  @route_macros [:get, :post, :put, :patch, :delete, :options, :head, :live, :forward, :resources]

  @doc """
  Marks each route inside a router `scope` with an alias, so a reader of
  `ast` can tell the module Phoenix will route to: in
  `scope "/", Brando do get "/robots.txt", SEOController, :robots end` the
  plug is `Brando.SEOController`.

  The route call's metadata starts with `scope_alias: [Brando]` (first, so
  a pattern can match it), the joined aliases of the scopes around it, as
  Phoenix joins them: a scope's alias is expanded through the aliases in
  scope where it is declared (`alias Brando, as: B` then `scope "/", B`, in
  the same module), a nested `scope "/x", Sub` adds `Sub`, a scope's
  positional alias wins over its `alias:` option, and `alias: false` starts
  over. `match :get, path, Plug, action` is marked like the verb macros.
  Routes with `alias: false` of their own, or outside any aliased scope, are
  left unmarked. Works on both `Code.string_to_quoted/2` and Sourceror ASTs.

  Module names come back annotated by `Brando.Deprecated.LexicalAliases`.
  """
  def mark_scoped_routes(ast), do: ast |> LexicalAliases.annotate() |> mark(%{scope: []})

  @doc """
  The module a route marked by `mark_scoped_routes/1` reaches: Phoenix
  expands the plug through the aliases in scope, then joins it to the
  scope's. Nil when the scope's alias or the plug cannot be resolved.
  """
  def scoped_module(:unknown, _plug), do: nil

  def scoped_module(scope, plug) do
    case LexicalAliases.module(plug) do
      nil -> nil
      module -> Module.concat(scope ++ [module])
    end
  end

  defp mark({:scope, meta, [_ | _] = args} = node, ctx) do
    {options, [block]} = Enum.split(args, -1)

    if do_block?(block) do
      {:scope, meta, options ++ [mark(block, %{ctx | scope: scope_alias(options, ctx)})]}
    else
      mark_children(node, ctx)
    end
  end

  defp mark({verb, meta, [path, {:__aliases__, _, _} = plug | rest]}, %{scope: scope} = ctx)
       when verb in @route_macros and scope != [] do
    {verb, scope_meta(meta, plug, rest, ctx), [path, plug | rest]}
  end

  defp mark({:match, meta, [verb, path, {:__aliases__, _, _} = plug | rest]}, %{scope: scope} = ctx) when scope != [] do
    {:match, scope_meta(meta, plug, rest, ctx), [verb, path, plug | rest]}
  end

  defp mark({_, _, args} = node, ctx) when is_list(args), do: mark_children(node, ctx)
  defp mark({left, right}, ctx), do: {mark(left, ctx), mark(right, ctx)}
  defp mark(list, ctx) when is_list(list), do: Enum.map(list, &mark(&1, ctx))
  defp mark(other, _ctx), do: other

  defp mark_children({call, meta, args}, ctx), do: {mark(call, ctx), meta, Enum.map(args, &mark(&1, ctx))}

  defp scope_meta(meta, {:__aliases__, _, parts}, rest, ctx) do
    if Enum.all?(parts, &is_atom/1) and not keyword_value?(rest, :alias, false),
      do: [{:scope_alias, ctx.scope} | meta],
      else: meta
  end

  # A positional alias wins: Phoenix's scope/3 and scope/4 put it over the
  # options' `alias:`. :unknown for an alias that cannot be resolved, and
  # for every scope under it
  defp scope_alias(options, ctx) do
    positional = Enum.find_value(options, &expand_alias/1)

    keyword =
      options
      |> Enum.map(&literal/1)
      |> Enum.find_value(:none, fn
        options when is_list(options) ->
          case keyword_value(options, :alias) do
            {:ok, false} -> :reset
            {:ok, value} -> expand_alias(value)
            :error -> nil
          end

        _ ->
          nil
      end)

    cond do
      positional -> join_scope(ctx.scope, positional)
      keyword == :reset -> []
      keyword in [nil, :none] -> ctx.scope
      true -> join_scope(ctx.scope, keyword)
    end
  end

  defp join_scope(scope, alias) when is_list(scope) and is_list(alias), do: scope ++ alias
  defp join_scope(_scope, _alias), do: :unknown

  defp expand_alias({:__aliases__, meta, _parts}) do
    case meta[:resolved_alias] do
      [_ | _] = parts -> parts
      _ -> :unknown
    end
  end

  defp expand_alias(_node), do: nil

  defp do_block?(block), do: is_list(block) and match?({:ok, _}, keyword_value(block, :do))

  # Bracketed options too: Sourceror wraps `[alias: false]` in a :__block__
  defp keyword_value?(args, key, value) do
    Enum.any?(args, fn arg ->
      arg = literal(arg)
      is_list(arg) and keyword_value(arg, key) == {:ok, value}
    end)
  end

  # Plain keyword lists, and Sourceror's, which wraps keys and literals in
  # :__block__ nodes
  defp keyword_value(list, key) do
    Enum.find_value(list, :error, fn
      {k, value} -> if literal(k) == key, do: {:ok, literal(value)}
      _ -> nil
    end)
  end

  defp literal({:__block__, _, [value]}), do: value
  defp literal(value), do: value
end

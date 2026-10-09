defmodule Brando.Deprecated.RenamedModules do
  @moduledoc false
  # Public modules renamed in 0.55 (#2833). Each old name is a deprecated
  # shim in `lib/brando/deprecated/` until it is removed in 0.57:
  # `mix brando.migrate55` rewrites references to the old names, and
  # `mix brando.doctor` lists the ones left in an application's `lib/`.
  #
  # Module atoms only, so nothing here depends on the modules at compile time.

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
  Phoenix joins them: the file's aliases are expanded (`alias Brando, as: B`
  then `scope "/", B`), a nested `scope "/x", Sub` adds `Sub`, a scope's
  positional alias wins over its `alias:` option, and `alias: false` starts
  over. `match :get, path, Plug, action` is marked like the verb macros.
  Routes with `alias: false` of their own, or outside any aliased scope, are
  left unmarked. Works on both `Code.string_to_quoted/2` and Sourceror ASTs.
  """
  def mark_scoped_routes(ast), do: mark(ast, %{scope: [], aliases: file_aliases(ast)})

  defp mark({:scope, meta, [_ | _] = args} = node, ctx) do
    {options, [block]} = Enum.split(args, -1)

    if do_block?(block) do
      {:scope, meta, options ++ [mark(block, %{ctx | scope: scope_alias(options, ctx)})]}
    else
      mark_children(node, ctx)
    end
  end

  defp mark({verb, meta, [path, {:__aliases__, _, _} = plug | rest]}, %{scope: [_ | _]} = ctx)
       when verb in @route_macros do
    {verb, scope_meta(meta, plug, rest, ctx), [path, plug | rest]}
  end

  defp mark({:match, meta, [verb, path, {:__aliases__, _, _} = plug | rest]}, %{scope: [_ | _]} = ctx) do
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
  # options' `alias:`
  defp scope_alias(options, ctx) do
    positional = Enum.find_value(options, &expand_alias(&1, ctx.aliases))

    keyword =
      options
      |> Enum.map(&literal/1)
      |> Enum.find_value(:none, fn
        options when is_list(options) ->
          case keyword_value(options, :alias) do
            {:ok, false} -> :reset
            {:ok, value} -> expand_alias(value, ctx.aliases)
            :error -> nil
          end

        _ ->
          nil
      end)

    cond do
      positional -> ctx.scope ++ positional
      keyword == :reset -> []
      is_list(keyword) -> ctx.scope ++ keyword
      true -> ctx.scope
    end
  end

  defp expand_alias({:__aliases__, _, [first | rest] = parts}, aliases) do
    if Enum.all?(parts, &is_atom/1), do: Map.get(aliases, first, [first]) ++ rest
  end

  defp expand_alias(_node, _aliases), do: nil

  # `short => parts` for the file's aliases, `as:` included
  defp file_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [{:__aliases__, _, parts} | options]} = node, aliases ->
          if Enum.all?(parts, &is_atom/1),
            do: {node, Map.put(aliases, alias_as(options) || parts |> Enum.reverse() |> hd(), parts)},
            else: {node, aliases}

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp alias_as([options]) when is_list(options) do
    case keyword_value(options, :as) do
      {:ok, {:__aliases__, _, [as]}} -> as
      _ -> nil
    end
  end

  defp alias_as(_options), do: nil

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

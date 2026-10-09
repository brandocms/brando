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

  @route_macros [:get, :post, :put, :patch, :delete, :options, :head, :match, :live, :forward, :resources]

  @doc """
  Marks each route inside a router `scope` with an alias, so a reader of
  `ast` can tell the module Phoenix will route to: in
  `scope "/", Brando do get "/robots.txt", SEOController, :robots end` the
  plug is `Brando.SEOController`.

  The route call's metadata starts with `scope_alias: [Brando]` (first, so
  a pattern can match it), the joined aliases
  of the scopes around it (a nested `scope "/x", Sub` adds `Sub`; a scope
  with `alias: false` starts over). Routes with `alias: false` of their own,
  or outside any aliased scope, are left unmarked. Works on both
  `Code.string_to_quoted/2` and Sourceror ASTs.
  """
  def mark_scoped_routes(ast), do: mark(ast, [])

  defp mark({:scope, meta, [_ | _] = args} = node, scope) do
    {options, [block]} = Enum.split(args, -1)

    if do_block?(block) do
      {:scope, meta, options ++ [mark(block, scope_alias(options, scope))]}
    else
      mark_children(node, scope)
    end
  end

  defp mark({verb, meta, [path, {:__aliases__, _, parts} = plug | rest]}, [_ | _] = scope)
       when verb in @route_macros do
    if Enum.all?(parts, &is_atom/1) and not keyword_value?(rest, :alias, false) do
      {verb, [{:scope_alias, scope} | meta], [path, plug | rest]}
    else
      {verb, meta, [path, plug | rest]}
    end
  end

  defp mark({_, _, args} = node, scope) when is_list(args), do: mark_children(node, scope)
  defp mark({left, right}, scope), do: {mark(left, scope), mark(right, scope)}
  defp mark(list, scope) when is_list(list), do: Enum.map(list, &mark(&1, scope))
  defp mark(other, _scope), do: other

  defp mark_children({call, meta, args}, scope), do: {mark(call, scope), meta, Enum.map(args, &mark(&1, scope))}

  defp scope_alias(options, scope) do
    Enum.reduce(options, scope, fn
      {:__aliases__, _, parts}, scope ->
        if Enum.all?(parts, &is_atom/1), do: scope ++ parts, else: scope

      options, scope when is_list(options) ->
        case keyword_value(options, :alias) do
          {:ok, {:__aliases__, _, parts}} -> scope ++ parts
          {:ok, false} -> []
          _ -> scope
        end

      _, scope ->
        scope
    end)
  end

  defp do_block?(block), do: is_list(block) and match?({:ok, _}, keyword_value(block, :do))

  defp keyword_value?(args, key, value), do: Enum.any?(args, &(is_list(&1) and keyword_value(&1, key) == {:ok, value}))

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

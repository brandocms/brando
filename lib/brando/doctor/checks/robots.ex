defmodule Brando.Doctor.Checks.Robots do
  @moduledoc """
  `/robots.txt` is served by Brando (`page_routes/1` in the router), so it
  carries the robots text from SEO settings and names the sitemap, and no
  static `priv/static/robots.txt` stands in front of it.

  A static file only stands in front when the endpoint's `Plug.Static` serves
  it: when its `only:` (or `only_matching:`) names it, or when it has neither.
  The check reads the endpoint's source for those options, whether a literal
  list (`only: ~w(assets js fonts images ico favicon.ico)`, the layout Brando's
  installer and pre-1.7 Phoenix write) or a call (`only: MyAppWeb.static_paths()`,
  Phoenix 1.7 and later), and names the one to change. Without the source, in
  a release, it can't tell and keeps the warning.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  @impl true
  def id, do: "robots"

  @impl true
  def label, do: dgettext("doctor", "robots.txt")

  @impl true
  def run(_context) do
    static =
      if static_file?() do
        {source, file} = endpoint_source()
        static_serving(source, file)
      else
        false
      end

    evaluate(route(), static)
  end

  @doc """
  `route` is the plug `/robots.txt` resolves to (or nil). `static` is `false`
  when there is no `priv/static/robots.txt`, or what `static_serving/2` says
  about it; `true` is taken as `{:unknown, nil}`.
  """
  def evaluate(route, static) do
    static = if static == true, do: {:unknown, nil}, else: static

    cond do
      # The deprecated `Brando.SEOController` still serves it; the
      # Deprecations check names the rename
      route not in [BrandoWeb.SEOController, Brando.SEOController] ->
        warning(dgettext("doctor", "not served by Brando"),
          fix: dgettext("doctor", "call page_routes() in the router's browser scope"),
          items: [dgettext("doctor", "GET /robots.txt goes to %{plug}", plug: inspect(route))]
        )

      match?({:served, _layout}, static) ->
        {:served, layout} = static

        warning(dgettext("doctor", "a static robots.txt stands in front of the SEO text"),
          fix: served_fix(layout),
          link: {BrandoAdmin.Sites.SEOLive, dgettext("doctor", "Open SEO")}
        )

      match?({:unknown, _layout}, static) ->
        warning(dgettext("doctor", "a static robots.txt may stand in front of the SEO text"),
          fix:
            dgettext(
              "doctor",
              "delete priv/static/robots.txt, and remove robots.txt from the only: list of the endpoint's Plug.Static (static_paths/0 in the web module on Phoenix 1.7 and later), if it is there"
            ),
          link: {BrandoAdmin.Sites.SEOLive, dgettext("doctor", "Open SEO")}
        )

      match?({:not_served, _layout}, static) ->
        {:not_served, layout} = static

        ok(dgettext("doctor", "served from SEO settings"),
          items: [
            dgettext("doctor", "priv/static/robots.txt is not served (not in %{setting}); delete it",
              setting: setting(layout)
            )
          ]
        )

      true ->
        ok(dgettext("doctor", "served from SEO settings"))
    end
  end

  defp served_fix({:all, file}),
    do:
      dgettext(
        "doctor",
        "delete priv/static/robots.txt: Plug.Static in %{file} has no only:, so it serves every file in priv/static",
        file: file
      )

  defp served_fix({_kind, _where, entry} = layout),
    do:
      dgettext("doctor", "delete priv/static/robots.txt and remove %{entry} from %{setting}",
        entry: entry,
        setting: setting(layout)
      )

  defp setting({:call, module, _entry}), do: "static_paths/0 in #{inspect(module)}"
  defp setting({option, file, _entry}), do: "Plug.Static's #{option}: in #{file}"

  @doc """
  Whether the endpoint's `Plug.Static` at `"/"` serves `robots.txt`, read from
  the endpoint's `source` (`file` is its path, for the message):

    * `{:served, layout}` or `{:not_served, layout}`, where `layout` says which
      setting decides: `{:only, file, entry}` and `{:only_matching, file, entry}`
      for a literal list, `{:call, module, entry}` for `only: module.fun()`,
      and `{:all, file}` when there is neither;
    * `{:unknown, nil}` when the source isn't there, or the list isn't a
      literal or a call to a loaded module.
  """
  @spec static_serving(String.t() | nil, String.t() | nil) :: {:served | :not_served | :unknown, term}
  def static_serving(source, file) when is_binary(source) do
    with {:ok, ast} <- Code.string_to_quoted(source),
         opts when is_list(opts) <- static_opts(ast) do
      decide(opts, file)
    else
      _ -> {:unknown, nil}
    end
  end

  def static_serving(_source, _file), do: {:unknown, nil}

  defp decide(opts, file) do
    only = Keyword.get(opts, :only)
    only_matching = Keyword.get(opts, :only_matching)

    lists = [only: list(only), only_matching: list(only_matching)]

    # Plug.Static serves everything when both lists are absent or empty.
    cond do
      Enum.any?(lists, fn {_option, value} -> value == :unknown end) -> {:unknown, nil}
      Enum.all?(lists, fn {_option, value} -> is_nil(value) or elem(value, 0) == [] end) -> {:served, {:all, file}}
      true -> lists |> Enum.reject(fn {_option, value} -> is_nil(value) or elem(value, 0) == [] end) |> verdict(file)
    end
  end

  defp verdict(lists, file) do
    match =
      Enum.find_value(lists, fn {option, {entries, where}} ->
        entry = Enum.find(entries, &serves?(option, &1))
        entry && layout(option, where, entry, file)
      end)

    case match do
      nil ->
        {option, {_entries, where}} = hd(lists)
        {:not_served, layout(option, where, nil, file)}

      layout ->
        {:served, layout}
    end
  end

  defp layout(:only, {:call, module}, entry, _file), do: {:call, module, entry}
  defp layout(option, _where, entry, file), do: {option, file, entry}

  # Plug.Static's `only:` matches the first path segment exactly;
  # `only_matching:` by prefix.
  defp serves?(:only, entry), do: entry == "robots.txt"
  defp serves?(:only_matching, entry), do: String.starts_with?("robots.txt", entry)

  defp list(nil), do: nil

  defp list({:sigil_w, _, [{:<<>>, _, [words]}, _modifiers]}) when is_binary(words),
    do: {String.split(words), :literal}

  defp list(entries) when is_list(entries) do
    if Enum.all?(entries, &is_binary/1), do: {entries, :literal}, else: :unknown
  end

  defp list({{:., _, [{:__aliases__, _, parts}, fun]}, _, []}) when is_atom(fun) do
    module = Module.concat(parts)

    with true <- Code.ensure_loaded?(module) and function_exported?(module, fun, 0),
         entries when is_list(entries) <- apply(module, fun, []) do
      {Enum.map(entries, &to_string/1), {:call, module}}
    else
      _ -> :unknown
    end
  end

  defp list(_other), do: :unknown

  # The options of the `plug Plug.Static` mounted at "/".
  defp static_opts(ast) do
    {_ast, found} =
      Macro.prewalk(ast, nil, fn
        {:plug, _, [{:__aliases__, _, [:Plug, :Static]}, opts]} = node, nil when is_list(opts) ->
          if Keyword.get(opts, :at) == "/", do: {node, opts}, else: {node, nil}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp endpoint_source do
    with endpoint when not is_nil(endpoint) <- Brando.endpoint(),
         true <- Code.ensure_loaded?(endpoint),
         path when is_list(path) <- endpoint.module_info(:compile)[:source],
         path = to_string(path),
         {:ok, source} <- File.read(path) do
      {source, Path.relative_to_cwd(path)}
    else
      _ -> {nil, nil}
    end
  rescue
    _ -> {nil, nil}
  end

  defp route do
    case Phoenix.Router.route_info(Brando.router(), "GET", "/robots.txt", nil) do
      %{plug: plug} -> plug
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp static_file? do
    case Brando.otp_app() do
      nil -> false
      app -> app |> Application.app_dir("priv/static/robots.txt") |> File.exists?()
    end
  rescue
    _ -> false
  end
end

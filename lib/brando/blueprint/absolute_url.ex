defmodule Brando.Blueprint.AbsoluteURL do
  @moduledoc """
  DSL macro for defining the absolute URL of a blueprint entry.

  Used for SEO, sitemaps, and admin preview links. The template receives
  the entry struct — use `@entry` in HEEx or `entry` in Liquex templates.

  Association references (e.g. `@entry.category.slug`) are automatically
  detected and included in `__absolute_url_preloads__/0`.

  ## HEEx (preferred)

  Use `route/2,3` for non-localized routes and `route_i18n/3,4` for
  locale-aware URLs:

      # Non-localized route
      absolute_url ~H|{route(:project_category_path, :detail, [@entry.slug])}|

      # Localized route (reads language from entry)
      absolute_url ~H|{route_i18n(@entry, :project_path, :detail, [@entry.slug])}|

      # Static path (no route helper)
      absolute_url ~H"/projects/{@entry.slug}"

      # Page routes (special handling — args split by `/`)
      absolute_url ~H|{route(:page_path, :show, [@entry.uri])}|

  ### When to use `route` vs `route_i18n`

  - `route/2,3` — schema has no `language` field, or routes should not be localized
  - `route_i18n/3,4` — schema uses `Brando.Trait.Translatable` and routes should
    include a locale prefix

  ### Indexed association access

  Use `Enum.at/2` for indexed access to association lists:

      absolute_url ~H|/projects/{Enum.at(@entry.properties, 0).slug}|

  ## Liquex (legacy)

      absolute_url "/projects/{{ entry.slug }}"

  ## i18n tuple (deprecated — use HEEx with `route_i18n` instead)

      absolute_url {:i18n, :project_path, :detail, [[:category, :slug], :slug]}

  ## Disabling

      absolute_url false

  ## Only some entries have a URL

  Some entries have no page on this site — a case that only links to the
  client, say. `only:` names the ones that do, in any of the forms above:

      absolute_url ~H"/projects/{@entry.slug}", only: %{type: :full_case}

  A map lists fields and the values they must equal, and gives both halves
  of the question from one declaration:

    * `__has_url__/1` — whether one entry has a URL on this site
    * `__url_filter__/0` — the same map, for a list query's `filter:`, as a
      sitemap needs

  `__absolute_url__/1` returns `nil` for the others, so nothing links to,
  sitemaps or audits a page that does not exist. A link elsewhere (an
  external URL field) is content, not the entry's URL.

  A one-arity function covers rules that are not plain equality. It answers
  `__has_url__/1` only; `__url_filter__/0` is `nil`, since a function
  cannot become a query:

      absolute_url ~H"/projects/{@entry.slug}", only: &(&1.external_url in [nil, ""])

  Without `only:` every entry has a URL, and `__url_filter__/0` is `nil`.
  """
  alias Brando.Blueprint.TemplateParser
  alias Brando.Exception.BlueprintError
  alias Brando.RuntimeConfig
  alias Brando.Villain

  @doc """
  Route helper for `absolute_url` HEEx templates. Calls the route helper
  directly without i18n localization.

  Special handling for `:page_path` with `:show` action — args are split by `/`.

  ## Examples

      absolute_url ~H|{route(:project_category_path, :detail, [@entry.slug])}|
      absolute_url ~H|{route(:page_path, :show, [@entry.uri])}|
  """
  def route(fun, action, args \\ [])

  def route(:page_path, :show, args) do
    prepared = Enum.map(args, &String.split(to_string(&1), "/"))
    apply(RuntimeConfig.router_helpers(), :page_path, [RuntimeConfig.endpoint(), :show] ++ prepared)
  end

  def route(fun, action, args) do
    apply(RuntimeConfig.router_helpers(), fun, [RuntimeConfig.endpoint(), action] ++ args)
  end

  @doc """
  I18n route helper for `absolute_url` HEEx templates. Reads `language` from
  the entry and uses `Brando.I18n.Helpers.localized_path/3` for locale-aware URLs.

  Special handling for `:page_path` — the page route is never localized via
  `localized_path` (no `:no_page_path` etc. exists). Instead, the language
  prefix is prepended manually, matching the behavior of the Liquex `route_i18n`
  tag. Args for `:show` action are split by `/`.

  ## Examples

      absolute_url ~H|{route_i18n(@entry, :project_path, :detail, [@entry.slug])}|
      absolute_url ~H|{route_i18n(@entry, :page_path, :show, [@entry.uri])}|
  """
  def route_i18n(entry, fun, action, args \\ [])

  def route_i18n(entry, :page_path, action, args) do
    path =
      case action do
        :show ->
          prepared = Enum.map(args, &String.split(to_string(&1), "/"))
          apply(RuntimeConfig.router_helpers(), :page_path, [RuntimeConfig.endpoint(), :show] ++ prepared)

        _ ->
          apply(RuntimeConfig.router_helpers(), :page_path, [RuntimeConfig.endpoint(), action] ++ args)
      end

    locale = to_string(entry.language)
    default_language = to_string(RuntimeConfig.get(:default_language))

    if RuntimeConfig.get(:scope_default_language_routes) == false && default_language == locale do
      path
    else
      "/#{locale}#{path}"
    end
  end

  def route_i18n(entry, fun, action, args) do
    Brando.I18n.Helpers.localized_path(
      entry.language,
      fun,
      [RuntimeConfig.endpoint(), action] ++ args
    )
  end

  defmacro absolute_url(false) do
    quote location: :keep do
      def __has_absolute_url__, do: false
    end
  end

  defmacro absolute_url(tpl) when is_binary(tpl) do
    parsed_absolute_url_tpl = TemplateParser.parse!(tpl, :absolute_url)

    quote location: :keep do
      @absolute_url_tpl unquote(tpl)
      @absolute_url_type :liquid
      @parsed_absolute_url_tpl unquote(parsed_absolute_url_tpl)
      def __absolute_url__(entry) do
        context =
          entry
          |> Villain.get_base_context()
          |> Liquex.Context.assign(:config, %{
            default_language: to_string(Brando.RuntimeConfig.get(:default_language)),
            scope_default_language_routes: Brando.RuntimeConfig.get(:scope_default_language_routes)
          })

        []
        |> Liquex.Render.render!(@parsed_absolute_url_tpl, context)
        |> elem(0)
        |> Enum.join()
        |> String.trim()
      rescue
        UndefinedFunctionError -> nil
        ArgumentError -> nil
      end

      def __absolute_url_template__ do
        unquote(tpl)
      end

      def __absolute_url_parsed__ do
        unquote(parsed_absolute_url_tpl)
      end

      def __absolute_url_type__, do: :liquid
      def __has_absolute_url__, do: true
    end
  end

  defmacro absolute_url({:sigil_H, _, [{:<<>>, _, [tpl_string]}, _]} = heex_ast) do
    quote location: :keep do
      @absolute_url_tpl unquote(tpl_string)
      @absolute_url_type :heex
      def __absolute_url__(entry) do
        import Brando.Blueprint.AbsoluteURL,
          only: [route: 2, route: 3, route_i18n: 3, route_i18n: 4]

        var!(assigns) = %{entry: entry}

        unquote(heex_ast)
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()
        |> String.trim()
      rescue
        UndefinedFunctionError -> nil
        ArgumentError -> nil
        KeyError -> nil
      end

      def __absolute_url_type__, do: :heex
      def __absolute_url_template__, do: unquote(tpl_string)
      def __has_absolute_url__, do: true
    end
  end

  defmacro absolute_url({:{}, _, [:i18n, fun, fun_target, args_tpl]}) do
    quote location: :keep do
      IO.warn(
        "absolute_url {:i18n, ...} is deprecated. Use HEEx with route_i18n/3 instead.",
        Macro.Env.stacktrace(__ENV__)
      )

      @absolute_url_tpl unquote(args_tpl)
      @absolute_url_type :i18n
      def __absolute_url__(entry) do
        locale =
          if Map.has_key?(entry, :language) do
            entry.language
          else
            Gettext.get_locale(Brando.RuntimeConfig.gettext())
          end

        # build args from args_tpl
        args =
          [
            Brando.RuntimeConfig.endpoint(),
            unquote(fun_target)
          ] ++
            Enum.map(unquote(args_tpl), fn
              keys when is_list(keys) ->
                get_in(entry, Enum.map(keys, &Access.key/1))

              key ->
                get_in(entry, [Access.key(key)])
            end)

        try do
          Brando.I18n.Helpers.localized_path(locale, unquote(fun), args)
        rescue
          UndefinedFunctionError -> nil
          ArgumentError -> nil
        end
      end

      def __absolute_url_type__, do: :i18n
      def __absolute_url_template__, do: unquote(args_tpl)
      def __has_absolute_url__, do: true
    end
  end

  defmacro absolute_url(value) do
    raise BlueprintError,
      message:
        "absolute_url expects a Liquid string, HEEx template, deprecated i18n tuple, or false, got: #{Macro.to_string(value)}"
  end

  defmacro absolute_url(false, _opts) do
    raise BlueprintError, message: "absolute_url false takes no options"
  end

  defmacro absolute_url(tpl, opts) do
    only =
      case opts do
        [only: only] -> only
        _ -> raise BlueprintError, message: "absolute_url accepts only: as its option, got: #{Macro.to_string(opts)}"
      end

    quote location: :keep do
      absolute_url(unquote(tpl))
      unquote(url_filter(only))

      defoverridable __absolute_url__: 1

      def __absolute_url__(entry) do
        if __has_url__(entry), do: super(entry)
      end
    end
  end

  defp url_filter({:%{}, _, _} = filter) do
    quote location: :keep do
      @url_filter unquote(filter)

      def __has_url__(entry) when is_map(entry) do
        Enum.all?(@url_filter, fn {key, value} -> Map.get(entry, key) == value end)
      end

      def __has_url__(_entry), do: false

      def __url_filter__, do: @url_filter
    end
  end

  defp url_filter(fun) do
    quote location: :keep do
      def __has_url__(entry), do: unquote(fun).(entry) == true
      def __url_filter__, do: nil
    end
  end
end

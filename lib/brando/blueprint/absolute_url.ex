defmodule Brando.Blueprint.AbsoluteURL do
  @moduledoc """
  Defines the absolute URL for the entry

  ## Examples

      absolute_url {:i18n, :project_path, :detail, [[:category, :slug], :slug]}

  or

      absolute_url "{% route_i18n entry.language project_path detail { entry.category.slug, entry.slug } %}"

  or

      absolute_url "/projects/{{ entry.id }}"

  """
  alias Brando.Villain

  defmacro absolute_url(false) do
    quote location: :keep do
      def __has_absolute_url__, do: false
    end
  end

  defmacro absolute_url(tpl) when is_binary(tpl) do
    {:ok, parsed_absolute_url} = Liquex.parse(tpl, Villain.LiquexParser)

    quote location: :keep do
      @parsed_absolute_url unquote(parsed_absolute_url)
      def __absolute_url__(entry) do
        context =
          entry
          |> Villain.get_base_context()
          |> Liquex.Context.assign(:config, %{
            default_language: to_string(Brando.config(:default_language)),
            scope_default_language_routes: Brando.config(:scope_default_language_routes)
          })

        []
        |> Liquex.Render.render!(@parsed_absolute_url, context)
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
        unquote(parsed_absolute_url)
      end

      def __absolute_url_type__, do: :liquid
      def __has_absolute_url__, do: true
    end
  end

  defmacro absolute_url({:{}, _, [:i18n, fun, fun_target, args_tpl]}) do
    quote location: :keep do
      def __absolute_url__(entry) do
        locale =
          if Map.has_key?(entry, :language) do
            entry.language
          else
            Gettext.get_locale(Brando.gettext())
          end

        # build args from args_tpl
        args =
          [
            Brando.endpoint(),
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

  @doc """
  Attempt to extract necessary preloads from absolute_url template
  """
  def extract_preloads_from_absolute_url(schema) do
    if schema.__has_absolute_url__() do
      type = schema.__absolute_url_type__()
      do_extract_preloads_from_absolute_url(type, schema)
    else
      []
    end
  end

  defp do_extract_preloads_from_absolute_url(:liquid, schema) do
    tpl = schema.__absolute_url_template__()
    regex = ~r/.*?(entry[.a-zA-Z0-9_]+).*?/

    matches =
      regex
      |> Regex.scan(tpl, capture: :all_but_first)
      |> Enum.map(&String.split(List.first(&1), "."))
      |> Enum.filter(&(Enum.count(&1) > 1))

    matches
    |> Enum.map(fn
      [_, rel, _] -> try_relation(schema, rel)
      [_, rel] -> try_relation(schema, rel)
    end)
    |> Enum.reject(&is_nil(&1))
    |> Enum.uniq()
  end

  defp do_extract_preloads_from_absolute_url(:i18n, schema) do
    tpl = schema.__absolute_url_template__()

    matches = Enum.filter(tpl, &(Enum.count(&1) > 1))

    matches
    |> Enum.map(fn
      [rel, _] -> try_relation(schema, rel)
      [rel] -> try_relation(schema, rel)
    end)
    |> Enum.reject(&is_nil(&1))
    |> Enum.uniq()
  end

  defp try_relation(schema, rel) when is_atom(rel) do
    %Brando.Blueprint.Relation{name: rel_name} = schema.__relation__(rel)
    rel_name
  rescue
    Brando.Exception.BlueprintError -> nil
  end

  defp try_relation(schema, rel) when is_binary(rel) do
    %Brando.Blueprint.Relation{name: rel_name} = schema.__relation__(String.to_existing_atom(rel))
    rel_name
  rescue
    Brando.Exception.BlueprintError -> nil
  end
end

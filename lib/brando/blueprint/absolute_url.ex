defmodule Brando.Blueprint.AbsoluteURL do
  @moduledoc """
  Defines the absolute URL for the entry

  ## Examples

      absolute_url "{% route_i18n entry.language project_path detail { entry.category.slug, entry.slug } %}"

  or

      absolute_url "/projects/{{ entry.id }}"

  """
  alias Brando.Villain

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
        UndefinedFunctionError -> "<no valid url found>"
        ArgumentError -> "<no valid url found>"
      end

      def __absolute_url_template__ do
        unquote(tpl)
      end
    end
  end
end

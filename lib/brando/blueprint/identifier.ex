defmodule Brando.Blueprint.Identifier do
  @moduledoc """
  Identifies the entry
  """
  defmacro identifier(tpl) when is_binary(tpl) do
    {:ok, parsed_identifier} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

    quote location: :keep do
      @parsed_identifier unquote(parsed_identifier)
      def __identifier__(entry) do
        context = Liquex.Context.assign(Brando.Villain.get_base_context(), "entry", entry)
        {result, _} = Liquex.Render.render([], @parsed_identifier, context)
        title = Enum.join(result)
        type = @singular
        translated_type = Gettext.dgettext(Brando.gettext(), "default", type)
        status = Map.get(entry, :status, nil)
        absolute_url = __MODULE__.__absolute_url__(entry)
        cover = Brando.Schema.extract_cover(entry)

        %{
          id: entry.id,
          title: title,
          type: translated_type,
          status: status,
          absolute_url: absolute_url,
          cover: cover,
          schema: __MODULE__
        }
      end
    end
  end
end

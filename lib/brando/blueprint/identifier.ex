defmodule Brando.Blueprint.Identifier do
  @moduledoc """
  Identifies the entry
  """

  @derive Jason.Encoder
  defstruct [:id, :title, :type, :status, :absolute_url, :cover, :schema]

  defmacro identifier(tpl) when is_binary(tpl) do
    {:ok, parsed_identifier} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

    quote location: :keep do
      @parsed_identifier unquote(parsed_identifier)
      def __identifier__(entry) do
        context = Liquex.Context.assign(Brando.Villain.get_base_context(), "entry", entry)
        {result, _} = Liquex.Render.render([], @parsed_identifier, context)
        title = Enum.join(result)

        translated_type =
          Brando.Utils.try_path(__MODULE__.__translations__(), [:naming, :singular]) || @singular

        status = Map.get(entry, :status, nil)
        absolute_url = __MODULE__.__absolute_url__(entry)
        cover = Brando.Blueprint.Identifier.extract_cover(entry)

        %Brando.Blueprint.Identifier{
          id: entry.id,
          title: title,
          type: String.capitalize(translated_type),
          status: status,
          absolute_url: absolute_url,
          cover: cover,
          schema: __MODULE__
        }
      end
    end
  end

  @spec identifiers_for([map]) :: {:ok, list}
  def identifiers_for(entries) do
    {:ok, Enum.map(entries, &identifier_for/1)}
  end

  def identifier_for(%{__struct__: schema} = entry) do
    schema.__identifier__(entry)
  end

  def extract_cover(%{cover: nil}) do
    nil
  end

  def extract_cover(%{cover: cover}) do
    Brando.Utils.img_url(cover, :thumb, prefix: Brando.Utils.media_url())
  end

  def extract_cover(_) do
    nil
  end
end

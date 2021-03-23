defmodule Brando.Blueprint.AbsoluteURL do
  @moduledoc """
  Absolute URL
  """
  defmacro absolute_url(tpl) when is_binary(tpl) do
    {:ok, parsed_absolute_url} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

    quote location: :keep do
      @parsed_absolute_url unquote(parsed_absolute_url)
      def __absolute_url__(entry) do
        context = Liquex.Context.assign(Brando.Villain.get_base_context(), "entry", entry)
        {result, _} = Liquex.Render.render([], @parsed_absolute_url, context)
        result
      end
    end
  end
end

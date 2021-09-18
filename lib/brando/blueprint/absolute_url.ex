defmodule Brando.Blueprint.AbsoluteURL do
  @moduledoc """
  Absolute URL
  """
  alias Brando.Villain

  defmacro absolute_url(tpl) when is_binary(tpl) do
    {:ok, parsed_absolute_url} = Liquex.parse(tpl, Villain.LiquexParser)

    quote location: :keep do
      @parsed_absolute_url unquote(parsed_absolute_url)
      def __absolute_url__(entry) do
        context = Villain.get_base_context(entry)

        []
        |> Liquex.Render.render(@parsed_absolute_url, context)
        |> elem(0)
        |> Enum.join()
        |> String.trim()
      end
    end
  end
end

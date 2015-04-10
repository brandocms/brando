defmodule Brando.Meta do
  defmacro __using__(opts) do
    quote do
      def __name__(:singular), do: unquote(opts[:singular])
      def __name__(:plural), do: unquote(opts[:plural])
      def __repr__(model), do: unquote(opts[:repr]).(model)
      use Linguist.Vocabulary
      locale "no", [model: unquote(opts[:fields])]
    end
  end
end
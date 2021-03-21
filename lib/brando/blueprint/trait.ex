defmodule Brando.Blueprint.Trait do
  defmacro trait(name, opts \\ []) do
    quote location: :keep, generated: true do
      case unquote(name) do
        :sequence ->
          use Brando.Sequence.Schema

        _ ->
          nil
      end

      require Logger
      Logger.error("==> updating @traits with #{unquote(name)}")
      @traits [unquote(name) | @traits]
      def __trait__(unquote(name)) do
        unquote(opts)
      end
    end
  end
end

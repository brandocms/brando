defmodule Brando.Blueprint.Trait do
  defmacro trait(name, opts \\ []) do
    quote location: :keep, generated: true do
      Module.put_attribute(__MODULE__, :traits, unquote(name))

      def __trait__(unquote(name)) do
        unquote(opts)
      end
    end
  end
end

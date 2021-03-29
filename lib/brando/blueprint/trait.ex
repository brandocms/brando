defmodule Brando.Blueprint.Trait do
  defmacro trait(name, opts \\ []) do
    quote location: :keep,
          generated: true do
      Module.put_attribute(__MODULE__, :traits, {unquote(name), unquote(opts)})
    end
  end
end

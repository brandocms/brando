defmodule Brando.Blueprint.Trait do
  @moduledoc false
  defmacro trait(name, opts \\ []) do
    [
      Macro.expand(name, __CALLER__).generate_code(__CALLER__.module, opts),
      quote location: :keep, generated: true do
        Module.put_attribute(__MODULE__, :traits, {unquote(name), unquote(opts)})
      end
    ]
  end
end

defmodule Brando.Auth.LayoutView do
  defmacro __using__(_) do
    quote do
      use Phoenix.View, root: Brando.config(:templates_path)
      # Use Phoenix.HTML to import all HTML functions (forms, tags, etc)
      use Phoenix.HTML
    end
  end
end
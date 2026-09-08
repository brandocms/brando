defmodule Brando.Content.Definition.Error do
  @moduledoc "An invalid or incomplete portable definition, with its source location."
  defexception [:message]

  @doc false
  def raise!(path, message), do: raise(__MODULE__, message: "#{path}: #{message}")
end

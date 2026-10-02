defmodule Brando.Trait.NoopCompiler do
  @moduledoc """
  Focused compile target for runtime-only traits that inject no Blueprint schema code.

  Custom traits whose behavior is limited to validation, changeset mutation, or save
  callbacks can opt in with `compile_with: Brando.Trait.NoopCompiler`.
  """

  @doc "Returns no schema code for a runtime-only trait."
  @spec generate_code(module(), keyword()) :: nil
  def generate_code(_schema, _opts), do: nil
end

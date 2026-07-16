defmodule Brando.Blueprint.Forms.ComponentResolver do
  @moduledoc """
  Resolves built-in symbolic Blueprint subform components at the admin render boundary.

  Blueprint schemas can store a small token instead of compile-depending on the
  corresponding admin LiveComponent. Custom component modules pass through unchanged.
  """

  @components %{
    gallery_objects: ["BrandoAdmin", "Components", "Form", "Input", "GalleryObjects"],
    identity_type_config: ["BrandoAdmin", "Components", "Form", "Input", "IdentityTypeConfig"],
    page_vars: ["BrandoAdmin", "Components", "Pages", "PageVars"],
    vars: ["BrandoAdmin", "Components", "Form", "Input", "Vars"]
  }

  @doc "Resolves a built-in token or returns a custom component module unchanged."
  def resolve(nil), do: nil

  def resolve(component) when is_map_key(@components, component) do
    @components
    |> Map.fetch!(component)
    |> Module.concat()
  end

  def resolve(component) when is_atom(component) do
    if component |> Atom.to_string() |> String.starts_with?("Elixir.") do
      component
    else
      raise ArgumentError,
            "unknown Blueprint form component #{inspect(component)}; " <>
              "expected one of #{inspect(Map.keys(@components))} or a component module"
    end
  end
end

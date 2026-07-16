defmodule Brando.Blueprint.FormComponentResolverTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.Forms.ComponentResolver
  alias Brando.Content.TableTemplate

  test "resolves built-in subform component tokens at runtime" do
    assert ComponentResolver.resolve(:vars) == BrandoAdmin.Components.Form.Input.Vars
    assert ComponentResolver.resolve(:gallery_objects) == BrandoAdmin.Components.Form.Input.GalleryObjects

    assert ComponentResolver.resolve(:identity_type_config) ==
             BrandoAdmin.Components.Form.Input.IdentityTypeConfig

    assert ComponentResolver.resolve(:page_vars) == BrandoAdmin.Components.Pages.PageVars
  end

  test "passes custom component modules through and rejects unknown tokens" do
    assert ComponentResolver.resolve(__MODULE__) == __MODULE__
    assert ComponentResolver.resolve(nil) == nil

    assert_raise ArgumentError, ~r/unknown Blueprint form component :missing/, fn ->
      ComponentResolver.resolve(:missing)
    end
  end

  test "Blueprint form metadata stores the lightweight token" do
    [_name_fieldset, vars_fieldset] = TableTemplate.__form__().tabs |> hd() |> Map.fetch!(:fields)
    [vars_subform] = vars_fieldset.fields

    assert vars_subform.component == :vars
  end
end

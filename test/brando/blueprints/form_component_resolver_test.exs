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

  test "Blueprint form metadata stores the RESOLVED module, without depending on it" do
    # This used to assert the stored value was still the `:vars` token. The
    # token exists so a Blueprint need not compile-depend on an admin
    # LiveComponent — but resolving it in `Forms.Dsl.transform_form/1` keeps
    # that property, because `Module.concat/1` yields a plain atom and the
    # compiler records no dependency edge for it. Verified with
    # `mix xref graph --sink .../input/vars.ex --label compile`, which lists
    # nothing. What the token bought at RENDER time was a `Module.concat/1` per
    # field per diff, which is what E3 in the form audit removed.
    [_name_fieldset, vars_fieldset] = TableTemplate.__form__().tabs |> hd() |> Map.fetch!(:fields)
    [vars_subform] = vars_fieldset.fields

    assert vars_subform.component == BrandoAdmin.Components.Form.Input.Vars
  end
end

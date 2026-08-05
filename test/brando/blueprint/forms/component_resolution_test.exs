defmodule Brando.Blueprint.Forms.ComponentResolutionTest do
  # Phase 3 / E3 in the form audit.
  #
  # `ComponentResolver` lets a Blueprint name an admin LiveComponent by token
  # instead of compile-depending on it. It was being called from
  # `Fieldset.Field.render/1`, so every field of every form paid a
  # `Module.concat/1` on every diff for a value fixed at Blueprint compile time.
  # `Forms.Dsl.transform_form/1` now resolves it once, into the entity.
  #
  # `resolve/1` itself is covered by `Brando.Blueprint.FormComponentResolverTest`;
  # this file covers what the COMPILED form carries.
  use ExUnit.Case, async: true

  defp fields(form) do
    for tab <- form.tabs, fieldset <- tab.fields, field <- fieldset.fields, do: field
  end

  test "a symbolic component token is a resolved module on the compiled form" do
    form = Brando.Galleries.Gallery.__form__(:default)

    subform = Enum.find(fields(form), &(&1.name == :gallery_objects))

    assert subform.component == BrandoAdmin.Components.Form.Input.GalleryObjects
    assert is_atom(subform.component)
    refute subform.component == :gallery_objects
  end

  test "fields without a component stay nil" do
    form = Brando.Pages.Page.__form__(:default)

    assert Enum.all?(fields(form), &(&1.component == nil or is_atom(&1.component)))
    assert Enum.any?(fields(form), &(&1.component == nil))
  end
end

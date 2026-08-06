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

  test "Blueprint form metadata stores the RESOLVED module" do
    # This used to assert the stored value was still the `:vars` token, which is
    # exactly what E3 in the form audit changed: `Forms.Dsl.transform_form/1`
    # now resolves it once at Blueprint compile time instead of per field per
    # diff. The property the token existed for is asserted separately below.
    [_name_fieldset, vars_fieldset] = TableTemplate.__form__().tabs |> hd() |> Map.fetch!(:fields)
    [vars_subform] = vars_fieldset.fields

    assert vars_subform.component == BrandoAdmin.Components.Form.Input.Vars
  end

  @sink "lib/brando_admin/components/form/input/vars.ex"

  test "and no Blueprint compile-depends on the admin component it names" do
    # THE property the `:vars` token bought — a Blueprint must not drag an admin
    # LiveComponent into its compile-time dependency graph. Resolving the token
    # preserves it because `Module.concat/1` yields a plain atom and the compiler
    # records no edge for it, but nothing in the type system says so, so assert
    # it rather than leave it to a one-off `mix xref` run in a comment.
    #
    # An empty graph is only meaningful if the sink actually exists — `--sink` on
    # a missing path prints nothing and would pass vacuously after a rename.
    assert File.exists?(@sink), "#{@sink} moved — update @sink or this test asserts nothing"

    {output, 0} =
      System.cmd("mix", ["xref", "graph", "--sink", @sink, "--label", "compile"],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert String.trim(output) == "",
           """
           A compile-time dependency on #{@sink} appeared. A Blueprint that \
           compile-depends on an admin LiveComponent recompiles the whole \
           Blueprint tree whenever that component changes.

           #{output}
           """
  end
end

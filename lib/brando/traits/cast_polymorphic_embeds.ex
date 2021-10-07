defmodule Brando.Trait.CastPolymorphicEmbeds do
  use Brando.Trait

  def changeset_mutator(module, _config, changeset, _user, _opts) do
    cast_poly(changeset, module.__poly_fields__())
  end

  defp cast_poly(changeset, poly_fields) do
    Enum.reduce(poly_fields, changeset, fn vf, mutated_changeset ->
      PolymorphicEmbed.cast_polymorphic_embed(mutated_changeset, vf.name)
    end)
  end
end

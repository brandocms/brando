defmodule Brando.Trait.CastPolymorphicEmbeds do
  use Brando.Trait

  def changeset_mutator(module, _config, changeset, _user) do
    Enum.reduce(module.__poly_fields__(), changeset, fn vf, mutated_changeset ->
      PolymorphicEmbed.cast_polymorphic_embed(mutated_changeset, vf.name)
    end)
  end
end

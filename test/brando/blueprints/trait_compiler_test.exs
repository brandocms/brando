defmodule Brando.Blueprint.TraitCompilerTest.CompilerAwareTrait.Compiler do
  @moduledoc false

  def generate_code(_schema, _opts) do
    quote do
      attributes do
        attribute :compiled_field, :string
      end
    end
  end
end

defmodule Brando.Blueprint.TraitCompilerTest.CompilerAwareTrait do
  @moduledoc false
  use Brando.Trait

  def generate_code(_schema, _opts) do
    quote do
      attributes do
        attribute :fallback_field, :string
      end
    end
  end
end

defmodule Brando.Blueprint.TraitCompilerTest.Schema do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "TraitCompilerTest",
    schema: "Schema",
    singular: "schema",
    plural: "schemas",
    gettext_module: Brando.Gettext

  trait Brando.Blueprint.TraitCompilerTest.CompilerAwareTrait,
    compile_with: Brando.Blueprint.TraitCompilerTest.CompilerAwareTrait.Compiler,
    runtime_option: :preserved
end

defmodule Brando.Blueprint.TraitCompilerTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.TraitCompilerTest.Schema

  test "uses an optional nested compiler without changing the runtime trait" do
    assert Brando.Blueprint.Attributes.__attribute__(Schema, :compiled_field)
    refute Brando.Blueprint.Attributes.__attribute__(Schema, :fallback_field)
    assert Schema.has_trait(Brando.Blueprint.TraitCompilerTest.CompilerAwareTrait)

    assert Schema.__trait__(Brando.Blueprint.TraitCompilerTest.CompilerAwareTrait) ==
             [runtime_option: :preserved]
  end

  test "the Sequenced compiler preserves its generated Blueprint attribute" do
    attribute = Brando.Blueprint.Attributes.__attribute__(Brando.Pages.Page, :sequence)

    assert attribute.type == :integer
    assert attribute.opts.default == 0
    assert Brando.Pages.Page.has_trait(Brando.Trait.Sequenced)
  end

  test "the Creator compiler preserves its generated Blueprint relation" do
    relation = Brando.Blueprint.Relations.__relation__(Brando.Pages.Page, :creator)

    assert relation.type == :belongs_to
    assert relation.opts.module == Brando.Users.User
    assert relation.opts.required
    assert Brando.Pages.Page.has_trait(Brando.Trait.Creator)
  end

  test "the SoftDelete compiler preserves its generated attribute and runtime options" do
    attribute = Brando.Blueprint.Attributes.__attribute__(Brando.Pages.Page, :deleted_at)

    assert attribute.type == :datetime
    assert Brando.Pages.Page.has_trait(Brando.Trait.SoftDelete)
    assert Brando.Pages.Page.__trait__(Brando.Trait.SoftDelete) == [obfuscated_fields: [:uri]]
  end

  test "the Status compiler preserves its generated Blueprint attribute" do
    attribute = Brando.Blueprint.Attributes.__attribute__(Brando.Pages.Page, :status)

    assert attribute.type == :status
    assert attribute.opts.required
    assert Brando.Pages.Page.has_trait(Brando.Trait.Status)
  end

  test "the Timestamped compiler preserves its generated Blueprint attributes" do
    inserted_at = Brando.Blueprint.Attributes.__attribute__(Brando.Pages.Page, :inserted_at)
    updated_at = Brando.Blueprint.Attributes.__attribute__(Brando.Pages.Page, :updated_at)

    assert inserted_at.type == :datetime
    assert updated_at.type == :datetime
    assert Brando.Pages.Page.has_trait(Brando.Trait.Timestamped)
  end

  test "the Translatable compiler preserves language and alternate behavior" do
    language = Brando.Blueprint.Attributes.__attribute__(Brando.Pages.Page, :language)
    alternates = Brando.Blueprint.Relations.__relation__(Brando.Pages.Page, :alternates)

    assert language.type == :language
    assert language.opts.required
    assert alternates.type == :has_many
    assert Brando.Pages.Page.has_alternates?()
    assert Brando.Pages.Page.Alternate.__schema__(:source) == "pages_alternates"
    refute Brando.Pages.Fragment.has_alternates?()

    assert Brando.Pages.Fragment.__trait__(Brando.Trait.Translatable) ==
             [alternates: false]
  end
end

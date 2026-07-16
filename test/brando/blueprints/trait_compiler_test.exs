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

defmodule Brando.Blueprint.TraitCompilerTest.RuntimeOnlyTrait do
  @moduledoc false
  use Brando.Trait
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

defmodule Brando.Blueprint.TraitCompilerTest.RuntimeOnlySchema do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "TraitCompilerTest",
    schema: "RuntimeOnlySchema",
    singular: "runtime_only_schema",
    plural: "runtime_only_schemas",
    gettext_module: Brando.Gettext

  trait Brando.Blueprint.TraitCompilerTest.RuntimeOnlyTrait,
    compile_with: Brando.Trait.NoopCompiler,
    runtime_option: :preserved
end

defmodule Brando.Blueprint.TraitCompilerTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.TraitCompilerTest.{RuntimeOnlySchema, Schema}

  test "uses an optional nested compiler without changing the runtime trait" do
    assert Brando.Blueprint.Attributes.__attribute__(Schema, :compiled_field)
    refute Brando.Blueprint.Attributes.__attribute__(Schema, :fallback_field)
    assert Schema.has_trait(Brando.Blueprint.TraitCompilerTest.CompilerAwareTrait)

    assert Schema.__trait__(Brando.Blueprint.TraitCompilerTest.CompilerAwareTrait) ==
             [runtime_option: :preserved]
  end

  test "a runtime-only trait can use the reusable no-op compiler" do
    assert RuntimeOnlySchema.has_trait(Brando.Blueprint.TraitCompilerTest.RuntimeOnlyTrait)

    assert RuntimeOnlySchema.__trait__(Brando.Blueprint.TraitCompilerTest.RuntimeOnlyTrait) ==
             [runtime_option: :preserved]
  end

  test "built-in runtime-only traits retain their runtime registration" do
    assert Brando.Content.Ref.has_trait(Brando.Trait.EnsureUID)
    assert Brando.Content.Module.has_trait(Brando.Trait.ValidateVarKeys)
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

  test "the Meta compiler preserves generated fields, assets, and runtime options" do
    title = Brando.Blueprint.Attributes.__attribute__(Brando.Pages.Page, :meta_title)
    description = Brando.Blueprint.Attributes.__attribute__(Brando.Pages.Page, :meta_description)
    image = Brando.Blueprint.Assets.__asset__(Brando.Pages.Page, :meta_image)

    assert title.type == :text
    assert description.type == :text
    assert image.type == :image
    assert Keyword.has_key?(Brando.Pages.Page.__trait__(Brando.Trait.Meta), :ai)
  end

  test "the ScheduledPublishing compiler preserves its generated Blueprint attribute" do
    attribute = Brando.Blueprint.Attributes.__attribute__(Brando.Pages.Page, :publish_at)

    assert attribute.type == :datetime
    assert Brando.Pages.Page.has_trait(Brando.Trait.ScheduledPublishing)
  end

  test "ScheduledPublishing keeps its runtime publish-time callback" do
    changeset = Ecto.Changeset.change(%Brando.Pages.Page{}, status: :published)

    updated_changeset = Brando.Trait.ScheduledPublishing.before_save(changeset, nil)

    assert %DateTime{} = Ecto.Changeset.get_change(updated_changeset, :publish_at)
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

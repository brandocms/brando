defmodule Brando.Blueprint.Identifier.HEExTest do
  use ExUnit.Case

  defmodule HEExIdentifierSchema do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Projects",
      schema: "HEExProject",
      singular: "heex_project",
      plural: "heex_projects",
      gettext_module: Brando.Gettext

    identifier ~H"{@entry.title} [{@entry.language}]"

    trait Brando.Trait.Status
    trait Brando.Trait.Timestamped

    attributes do
      attribute :title, :string, required: true
      attribute :language, :string
    end

    absolute_url false
  end

  defmodule HEExAbsoluteURLSchema do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Projects",
      schema: "HEExURLProject",
      singular: "heex_url_project",
      plural: "heex_url_projects",
      gettext_module: Brando.Gettext

    identifier ~H"{@entry.title} [{@entry.category.title}]"

    absolute_url ~H"/projects/{@entry.category.slug}/{@entry.slug}"

    trait Brando.Trait.Status
    trait Brando.Trait.Timestamped

    attributes do
      attribute :title, :string, required: true
      attribute :slug, :slug, required: true
    end

    relations do
      relation :category, :belongs_to, module: Brando.BlueprintTest.Project
    end
  end

  describe "identifier with ~H" do
    test "__has_identifier__ returns true" do
      assert HEExIdentifierSchema.__has_identifier__() == true
    end

    test "__identifier__ generates correct identifier struct" do
      entry = %HEExIdentifierSchema{
        id: 1,
        title: "Hello World",
        language: "en",
        status: :published
      }

      identifier = HEExIdentifierSchema.__identifier__(entry)
      assert identifier.title == "Hello World [en]"
      assert identifier.entry_id == 1
      assert identifier.status == :published
      assert identifier.schema == HEExIdentifierSchema
    end

    test "__identifier__ with skip_cover option" do
      entry = %HEExIdentifierSchema{
        id: 2,
        title: "Test",
        language: "no",
        status: :draft
      }

      identifier = HEExIdentifierSchema.__identifier__(entry, skip_cover: true)
      assert identifier.title == "Test [no]"
      assert identifier.cover == nil
    end
  end

  describe "absolute_url with ~H" do
    test "__has_absolute_url__ returns true" do
      assert HEExAbsoluteURLSchema.__has_absolute_url__() == true
    end

    test "__absolute_url_type__ returns :heex" do
      assert HEExAbsoluteURLSchema.__absolute_url_type__() == :heex
    end

    test "__absolute_url__ generates correct URL" do
      entry = %HEExAbsoluteURLSchema{
        id: 1,
        title: "Test",
        slug: "test-project",
        status: :published,
        category: %{slug: "art"}
      }

      assert HEExAbsoluteURLSchema.__absolute_url__(entry) == "/projects/art/test-project"
    end

    test "__absolute_url_preloads__ extracts relation preloads from HEEx template" do
      assert HEExAbsoluteURLSchema.__absolute_url_preloads__() == [:category]
    end
  end

  describe "preloads" do
    test "__identifier_preloads__ returns empty for simple HEEx identifier" do
      assert HEExIdentifierSchema.__identifier_preloads__() == []
    end

    test "__identifier_preloads__ extracts relation preloads from HEEx identifier" do
      assert HEExAbsoluteURLSchema.__identifier_preloads__() == [:category]
    end
  end
end

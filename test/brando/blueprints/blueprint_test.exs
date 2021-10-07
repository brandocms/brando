defmodule Brando.Blueprint.BlueprintTest do
  use ExUnit.Case
  alias Brando.Blueprint.Asset
  alias Brando.Blueprint.Attribute
  alias Brando.Blueprint.Relation

  test "naming" do
    assert Brando.BlueprintTest.Project.__naming__().application == "Brando"
    assert Brando.BlueprintTest.Project.__naming__().domain == "Projects"
    assert Brando.BlueprintTest.Project.__naming__().schema == "Project"
    assert Brando.BlueprintTest.Project.__naming__().singular == "project"
    assert Brando.BlueprintTest.Project.__naming__().plural == "projects"
  end

  test "modules" do
    assert Brando.BlueprintTest.Project.__modules__(:application) == Brando
    assert Brando.BlueprintTest.Project.__modules__(:context) == Brando.Projects
    assert Brando.BlueprintTest.Project.__modules__(:schema) == Brando.Projects.Project
  end

  test "traits" do
    assert Brando.BlueprintTest.Project.__traits__() == [
             {Brando.Trait.Creator, []},
             {Brando.Trait.SoftDelete, []},
             {Brando.Trait.Sequenced, []},
             {Brando.Trait.Timestamped, []}
           ]
  end

  test "changeset mutators" do
    mutated_cs =
      Brando.BlueprintTest.Project.changeset(
        %Brando.BlueprintTest.Project{},
        %{title: "my title", slug: "my-title"},
        %{id: 1}
      )

    assert mutated_cs.changes.creator_id == 1
    assert mutated_cs.changes.title == "my title"
  end

  test "__required_attrs__" do
    required_attrs = Brando.BlueprintTest.Project.__required_attrs__()
    assert required_attrs == [:slug, :creator_id]
  end

  test "__optional_attrs__" do
    optional_attrs = Brando.BlueprintTest.Project.__optional_attrs__()
    assert optional_attrs == [:title, :deleted_at, :sequence, :updated_at, :inserted_at]
  end

  test "attributes" do
    attrs = Brando.BlueprintTest.Project.__attributes__()

    assert attrs == [
             %Attribute{name: :title, opts: %{}, type: :string},
             %Attribute{
               name: :slug,
               opts: %{from: :title, required: true},
               type: :slug
             },
             %Attribute{name: :deleted_at, opts: %{}, type: :datetime},
             %Attribute{
               name: :sequence,
               opts: %{default: 0},
               type: :integer
             },
             %Brando.Blueprint.Attribute{name: :updated_at, opts: %{}, type: :datetime},
             %Brando.Blueprint.Attribute{name: :inserted_at, opts: %{}, type: :datetime}
           ]
  end

  test "attribute_opts" do
    attr_opts = Brando.BlueprintTest.Project.__attribute_opts__(:slug)
    assert attr_opts == %{from: :title, required: true}
  end

  test "assets" do
    assets = Brando.BlueprintTest.Project.__assets__()

    assert assets == [
             %Asset{
               name: :cover,
               opts: %{
                 module: Brando.Images.Image,
                 cfg: %Brando.Type.ImageConfig{
                   allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
                   default_size: "medium",
                   random_filename: true,
                   size_limit: 10_240_000,
                   sizes: %{
                     "large" => %{"crop" => true, "quality" => 65, "size" => "700x700"},
                     "medium" => %{"crop" => true, "quality" => 65, "size" => "500x500"},
                     "micro" => %{"crop" => false, "quality" => 10, "size" => "25"},
                     "small" => %{"crop" => true, "quality" => 65, "size" => "300x300"},
                     "thumb" => %{"crop" => true, "quality" => 65, "size" => "150x150"},
                     "xlarge" => %{"crop" => true, "quality" => 65, "size" => "900x900"}
                   },
                   srcset: [{"small", "300w"}, {"medium", "500w"}, {"large", "700w"}],
                   target_format: nil,
                   upload_path: "images/avatars"
                 }
               },
               type: :image
             }
           ]
  end

  test "asset_opts" do
    %{cfg: cfg} = Brando.BlueprintTest.Project.__asset_opts__(:cover)

    assert cfg == %Brando.Type.ImageConfig{
             allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
             default_size: "medium",
             random_filename: true,
             size_limit: 10_240_000,
             sizes: %{
               "large" => %{"crop" => true, "quality" => 65, "size" => "700x700"},
               "medium" => %{"crop" => true, "quality" => 65, "size" => "500x500"},
               "micro" => %{"crop" => false, "quality" => 10, "size" => "25"},
               "small" => %{"crop" => true, "quality" => 65, "size" => "300x300"},
               "thumb" => %{"crop" => true, "quality" => 65, "size" => "150x150"},
               "xlarge" => %{"crop" => true, "quality" => 65, "size" => "900x900"}
             },
             srcset: [{"small", "300w"}, {"medium", "500w"}, {"large", "700w"}],
             upload_path: "images/avatars",
             target_format: nil
           }
  end

  test "relations" do
    relations = Brando.BlueprintTest.Project.__relations__()

    assert relations == [
             %Brando.Blueprint.Relation{
               name: :properties,
               opts: %{module: Brando.BlueprintTest.Property},
               type: :embeds_many
             },
             %Relation{
               name: :creator,
               opts: %{module: Brando.Users.User, required: true},
               type: :belongs_to
             }
           ]
  end

  test "ecto schema" do
    schema = Brando.BlueprintTest.Project.__schema__(:fields)

    assert schema == [
             :id,
             :title,
             :slug,
             :deleted_at,
             :sequence,
             :inserted_at,
             :updated_at,
             :cover,
             :properties,
             :creator_id
           ]
  end
end

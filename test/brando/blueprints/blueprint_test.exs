defmodule Brando.Blueprint.BlueprintTest do
  use ExUnit.Case
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
               opts: %{required: true},
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
    assert attr_opts == %{required: true}
  end

  test "assets" do
    assets = Brando.BlueprintTest.Project.__assets__()

    assert assets == [
             %Brando.Blueprint.Asset{
               name: :cover,
               opts: %{
                 cfg: %Brando.Type.ImageConfig{
                   allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
                   cdn: nil,
                   default_size: "medium",
                   formats: [:original],
                   overwrite: false,
                   random_filename: true,
                   size_limit: 10_240_000,
                   sizes: %{
                     "crop_medium" => %{"crop" => true, "quality" => 65, "size" => "500x500"},
                     "crop_small" => %{"crop" => true, "quality" => 65, "size" => "300x300"},
                     "large" => %{"crop" => true, "quality" => 65, "size" => "700x700"},
                     "medium" => %{"crop" => true, "quality" => 65, "size" => "500x500"},
                     "micro" => %{"crop" => false, "quality" => 10, "size" => "25"},
                     "small" => %{"crop" => true, "quality" => 65, "size" => "300x300"},
                     "thumb" => %{"crop" => true, "quality" => 65, "size" => "150x150"},
                     "xlarge" => %{"crop" => true, "quality" => 65, "size" => "900x900"}
                   },
                   srcset: %{
                     cropped: [{"crop_small", "300w"}, {"crop_medium", "500w"}],
                     default: [
                       {"small", "300w"},
                       {"medium", "500w"},
                       {"large", "700w"},
                       {"xlarge", "900w"}
                     ]
                   },
                   upload_path: "images/avatars"
                 },
                 module: Brando.Images.Image
               },
               type: :image
             },
             %Brando.Blueprint.Asset{
               name: :cover_cdn,
               opts: %{
                 cfg: %Brando.Type.ImageConfig{
                   allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
                   cdn: %{enabled: true, media_url: "https://mycustomcdn.com", s3: :default},
                   default_size: "medium",
                   formats: [:original],
                   overwrite: false,
                   random_filename: true,
                   size_limit: 10_240_000,
                   sizes: %{
                     "large" => %{"quality" => 75, "size" => "1700"},
                     "medium" => %{"quality" => 75, "size" => "1100"},
                     "micro" => %{"crop" => false, "quality" => 20, "size" => "25"},
                     "small" => %{"quality" => 75, "size" => "700"},
                     "thumb" => %{"crop" => true, "quality" => 75, "size" => "400x400>"},
                     "xlarge" => %{"quality" => 65, "size" => "2800"},
                     "crop_xlarge" => %{"crop" => true, "quality" => 65, "size" => "1000x500"}
                   },
                   srcset: %{cropped: [{"crop_xlarge", "900w"}], default: [{"xlarge", "900w"}]},
                   upload_path: "images/avatars"
                 },
                 module: Brando.Images.Image
               },
               type: :image
             },
             %Brando.Blueprint.Asset{
               name: :pdf,
               opts: %{
                 cfg: %Brando.Type.FileConfig{
                   accept: :any,
                   allowed_mimetypes: ["application/pdf"],
                   force_filename: nil,
                   overwrite: false,
                   random_filename: false,
                   size_limit: 10_240_000,
                   upload_path: "files/projects"
                 },
                 module: Brando.Files.File
               },
               type: :file
             }
           ]
  end

  test "asset_opts" do
    %{cfg: cfg} = Brando.BlueprintTest.Project.__asset_opts__(:cover)

    assert cfg == %Brando.Type.ImageConfig{
             allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
             default_size: "medium",
             formats: [:original],
             overwrite: false,
             random_filename: true,
             size_limit: 10_240_000,
             sizes: %{
               "large" => %{"crop" => true, "quality" => 65, "size" => "700x700"},
               "medium" => %{"crop" => true, "quality" => 65, "size" => "500x500"},
               "micro" => %{"crop" => false, "quality" => 10, "size" => "25"},
               "small" => %{"crop" => true, "quality" => 65, "size" => "300x300"},
               "thumb" => %{"crop" => true, "quality" => 65, "size" => "150x150"},
               "xlarge" => %{"crop" => true, "quality" => 65, "size" => "900x900"},
               "crop_medium" => %{"crop" => true, "quality" => 65, "size" => "500x500"},
               "crop_small" => %{"crop" => true, "quality" => 65, "size" => "300x300"}
             },
             srcset: %{
               cropped: [
                 {"crop_small", "300w"},
                 {"crop_medium", "500w"}
               ],
               default: [
                 {"small", "300w"},
                 {"medium", "500w"},
                 {"large", "700w"},
                 {"xlarge", "900w"}
               ]
             },
             upload_path: "images/avatars"
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
             :cover_id,
             :cover_cdn_id,
             :pdf_id,
             :properties,
             :creator_id
           ]
  end
end

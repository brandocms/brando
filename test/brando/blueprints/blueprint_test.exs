defmodule Brando.Blueprint.BlueprintTest do
  use ExUnit.Case

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
             {Brando.Trait.Status, []},
             {Brando.Trait.Timestamped, []},
             {Brando.Trait.Translatable, []}
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
    assert required_attrs == [:language, :slug, :status]
  end

  test "__optional_attrs__" do
    optional_attrs = Brando.BlueprintTest.Project.__optional_attrs__()
    assert optional_attrs == [:deleted_at, :inserted_at, :sequence, :title, :updated_at]
  end

  test "attributes" do
    attrs = Brando.Blueprint.Attributes.__attributes__(Brando.BlueprintTest.Project)

    assert attrs == [
             %Brando.Blueprint.Attributes.Attribute{
               __identifier__: :status,
               name: :status,
               type: :status,
               opts: %{required: true}
             },
             %Brando.Blueprint.Attributes.Attribute{
               __identifier__: :language,
               name: :language,
               type: :language,
               opts: %{values: [:no, :en], required: true}
             },
             %Brando.Blueprint.Attributes.Attribute{
               __identifier__: :title,
               name: :title,
               opts: %{},
               type: :string
             },
             %Brando.Blueprint.Attributes.Attribute{
               __identifier__: :slug,
               name: :slug,
               opts: %{required: true},
               type: :slug
             },
             %Brando.Blueprint.Attributes.Attribute{
               __identifier__: :deleted_at,
               name: :deleted_at,
               opts: %{},
               type: :datetime
             },
             %Brando.Blueprint.Attributes.Attribute{
               __identifier__: :sequence,
               name: :sequence,
               opts: %{default: 0},
               type: :integer
             },
             %Brando.Blueprint.Attributes.Attribute{
               __identifier__: :inserted_at,
               name: :inserted_at,
               opts: %{},
               type: :datetime
             },
             %Brando.Blueprint.Attributes.Attribute{
               __identifier__: :updated_at,
               name: :updated_at,
               opts: %{},
               type: :datetime
             }
           ]
  end

  test "attribute_opts" do
    attr_opts =
      Brando.Blueprint.Attributes.__attribute_opts__(Brando.BlueprintTest.Project, :slug)

    assert attr_opts == %{required: true}
  end

  test "assets" do
    assets = Brando.Blueprint.Assets.__assets__(Brando.BlueprintTest.Project)

    assert assets == [
             %Brando.Blueprint.Assets.Asset{
               __identifier__: :cover,
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
             %Brando.Blueprint.Assets.Asset{
               __identifier__: :cover_cdn,
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
             %Brando.Blueprint.Assets.Asset{
               __identifier__: :pdf,
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
    %{cfg: cfg} = Brando.Blueprint.Assets.__asset_opts__(Brando.BlueprintTest.Project, :cover)

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
    relations = Brando.Blueprint.Relations.__relations__(Brando.BlueprintTest.Project)

    assert relations == [
             %Brando.Blueprint.Relations.Relation{
               __identifier__: :creator,
               name: :creator,
               opts: %{module: Brando.Users.User, required: true},
               type: :belongs_to
             },
             %Brando.Blueprint.Relations.Relation{
               name: :alternates,
               type: :has_many,
               opts: %{module: :alternates},
               __identifier__: :alternates
             },
             %Brando.Blueprint.Relations.Relation{
               __identifier__: :properties,
               name: :properties,
               opts: %{module: Brando.BlueprintTest.Property},
               type: :embeds_many
             }
           ]
  end

  test "ecto schema" do
    schema = Brando.BlueprintTest.Project.__schema__(:fields)

    assert schema == [
             :id,
             :status,
             :language,
             :title,
             :slug,
             :deleted_at,
             :sequence,
             :inserted_at,
             :updated_at,
             :cover_id,
             :cover_cdn_id,
             :pdf_id,
             :creator_id,
             :properties
           ]
  end
end

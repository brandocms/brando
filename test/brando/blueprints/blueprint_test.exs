defmodule Brando.Blueprint.BlueprintTest do
  use ExUnit.Case

  defmodule Project do
    use Brando.Blueprint

    application "Brando"
    domain "Projects"
    schema "Project"
    singular "project"
    plural "projects"

    trait Brando.Traits.Creator
    trait Brando.Traits.SoftDelete
    trait Brando.Traits.Sequence
    trait Brando.Traits.Upload

    attributes do
      attribute :title, :string
      attribute :slug, :slug, from: :title, required: true

      attribute :cover, :image,
        allowed_mimetypes: [
          "image/jpeg",
          "image/png",
          "image/gif"
        ],
        default_size: "medium",
        upload_path: Path.join("images", "avatars"),
        random_filename: true,
        size_limit: 10_240_000,
        sizes: %{
          "micro" => %{"size" => "25", "quality" => 10, "crop" => false},
          "thumb" => %{"size" => "150x150", "quality" => 65, "crop" => true},
          "small" => %{"size" => "300x300", "quality" => 65, "crop" => true},
          "medium" => %{"size" => "500x500", "quality" => 65, "crop" => true},
          "large" => %{"size" => "700x700", "quality" => 65, "crop" => true},
          "xlarge" => %{"size" => "900x900", "quality" => 65, "crop" => true}
        },
        srcset: [
          {"small", "300w"},
          {"medium", "500w"},
          {"large", "700w"}
        ]
    end

    relations do
    end
  end

  test "naming" do
    assert __MODULE__.Project.__application__() == "Brando"
    assert __MODULE__.Project.__domain__() == "Projects"
    assert __MODULE__.Project.__schema__() == "Project"
    assert __MODULE__.Project.__singular__() == "project"
    assert __MODULE__.Project.__plural__() == "projects"
  end

  test "modules" do
    assert __MODULE__.Project.__modules__(:application) == Brando
    assert __MODULE__.Project.__modules__(:context) == Brando.Projects
    assert __MODULE__.Project.__modules__(:schema) == Brando.Projects.Project
  end

  test "traits" do
    assert __MODULE__.Project.__traits__() == [
             Brando.Traits.Creator,
             Brando.Traits.SoftDelete,
             Brando.Traits.Sequence,
             Brando.Traits.Upload
           ]
  end

  test "changeset mutators" do
    mutated_cs =
      __MODULE__.Project.changeset(
        %__MODULE__.Project{},
        %{title: "my title", slug: "my-title"},
        %{id: 1}
      )

    assert mutated_cs.changes.creator_id == 1
    assert mutated_cs.changes.title == "my title"
  end

  test "__required_attrs__" do
    required_attrs = __MODULE__.Project.__required_attrs__()
    assert required_attrs == [:slug, :creator_id]
  end

  test "__optional_attrs__" do
    optional_attrs = __MODULE__.Project.__optional_attrs__()
    assert optional_attrs == [:title, :cover, :deleted_at, :sequence]
  end

  test "attributes" do
    attrs = __MODULE__.Project.__attributes__()

    assert attrs == [
             %{name: :title, opts: [], type: :string},
             %{name: :slug, opts: [from: :title, required: true], type: :slug},
             %{
               name: :cover,
               opts: [
                 allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
                 default_size: "medium",
                 upload_path: "images/avatars",
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
                 srcset: [{"small", "300w"}, {"medium", "500w"}, {"large", "700w"}]
               ],
               type: :image
             },
             %{name: :deleted_at, opts: [], type: :datetime},
             %{name: :sequence, opts: [default: 0], type: :integer}
           ]
  end

  test "attribute_opts" do
    attr_opts = __MODULE__.Project.__attribute_opts__(:slug)
    assert attr_opts == [from: :title, required: true]

    attr_opts = __MODULE__.Project.__attribute_opts__(:cover)

    assert attr_opts == [
             {
               :allowed_mimetypes,
               ["image/jpeg", "image/png", "image/gif"]
             },
             {:default_size, "medium"},
             {:upload_path, "images/avatars"},
             {:random_filename, true},
             {:size_limit, 10_240_000},
             {:sizes,
              %{
                "large" => %{"crop" => true, "quality" => 65, "size" => "700x700"},
                "medium" => %{"crop" => true, "quality" => 65, "size" => "500x500"},
                "micro" => %{"crop" => false, "quality" => 10, "size" => "25"},
                "small" => %{"crop" => true, "quality" => 65, "size" => "300x300"},
                "thumb" => %{"crop" => true, "quality" => 65, "size" => "150x150"},
                "xlarge" => %{"crop" => true, "quality" => 65, "size" => "900x900"}
              }},
             {:srcset, [{"small", "300w"}, {"medium", "500w"}, {"large", "700w"}]}
           ]
  end

  test "relations" do
    relations = __MODULE__.Project.__relations__()

    assert relations == [
             %{
               name: :creator,
               opts: [module: Brando.Users.User, required: true],
               type: :belongs_to
             }
           ]
  end

  test "ecto schema" do
    schema = __MODULE__.Project.__schema__(:fields)
    assert schema == [:id, :title, :slug, :cover, :deleted_at, :sequence, :creator_id]
  end
end

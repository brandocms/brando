defmodule E2eProject.Projects.InlineRow do
  @moduledoc """
  A fixture row carrying one of every input an inline subform can put on a
  line, so `style :inline` is laid out and tested against all of them at once.
  Shown under the client form's "Inline fields" tab.

  Link, multi-select, gallery and entries inputs need their own relations and
  are covered by the menus, form builder and project forms instead.
  """

  use Brando.Blueprint,
    application: "E2eProject",
    domain: "Projects",
    schema: "InlineRow",
    singular: "inline_row",
    plural: "inline_rows"

  trait Brando.Trait.Sequenced
  trait Brando.Trait.Status

  identifier false
  persist_identifier false
  table "projects_inline_rows"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug
    attribute :key, :string
    attribute :notes, :text
    attribute :email, :string
    attribute :phone, :string
    attribute :amount, :integer
    attribute :starts_on, :date
    attribute :starts_at, :datetime
    attribute :color, :string
    attribute :featured, :boolean, default: false
    attribute :confirmed, :boolean, default: false
    attribute :kind, :string
    attribute :size, :string
    attribute :aliases, Brando.Type.StringList
  end

  assets do
    asset :cover, :image,
      cfg: %{
        upload_path: Path.join(["images", "projects", "inline_rows"]),
        sizes: %{
          "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
          "thumb" => %{"size" => "300x300>", "quality" => 70, "crop" => true}
        }
      }

    asset :attachment, :file,
      cfg: %{
        allowed_mimetypes: ["application/pdf"],
        upload_path: Path.join(["files", "projects", "inline_rows"])
      }

    asset :clip, :video,
      cfg: %{
        upload_path: Path.join(["videos", "projects", "inline_rows"])
      }
  end

  relations do
    relation :client, :belongs_to, module: E2eProject.Projects.Client
  end

  translations do
    context :naming do
      translate :singular, t("inline row")
      translate :plural, t("inline rows")
    end
  end
end

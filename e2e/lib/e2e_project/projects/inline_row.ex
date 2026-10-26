defmodule E2eProject.Projects.InlineRow do
  @moduledoc """
  A fixture row carrying one of every input an inline subform can put on a
  line, so `style :inline` is laid out and tested against all of them at once.
  Shown under the client form's "Inline fields" tab.

  Link, relation multi-select, gallery and entries inputs need their own relations and
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
    attribute :aliases, :string_list
    attribute :tags, {:array, :string}
    attribute :label, :i18n_string
    attribute :description, :i18n_string
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

  # Every input of the row on its own, declared locked, alternating
  # `readonly: true` and `disabled: true` (locked-inputs.spec.js). Opened at
  # /admin/projects/inline_rows/locked/:entry_id.
  forms do
    form :locked do
      tab "Locked" do
        fieldset do
          size :half
          input :status, :status, readonly: true
          input :title, :text, label: "Title", readonly: true
          input :key, :code, label: "Key", disabled: true
          input :notes, :textarea, label: "Notes", readonly: true
          input :email, :email, label: "Email", disabled: true
          input :phone, :phone, label: "Phone", readonly: true
          input :amount, :number, label: "Amount", disabled: true
          input :starts_on, :date, label: "Date", readonly: true
          input :starts_at, :datetime, label: "Date and time", disabled: true
          input :color, :color, label: "Colour", readonly: true
          input :kind, :select, label: "Kind", options: &E2eProject.Projects.Client.kind_options/2, disabled: true
          input :size, :radios, label: "Size", options: &E2eProject.Projects.Client.size_options/2, readonly: true
        end

        fieldset do
          size :half
          input :featured, :toggle, label: "Featured", disabled: true
          input :confirmed, :checkbox, label: "Confirmed", readonly: true
          input :aliases, :string_list, label: "Aliases", disabled: true

          input :tags, :multi_select,
            label: "Tags",
            options: [%{label: "Red", value: "red"}, %{label: "Green", value: "green"}],
            readonly: true

          input :label, :i18n_text, label: "Label", disabled: true
          input :description, :i18n_textarea, label: "Description", readonly: true
          input :cover, :image, label: "Image", disabled: true
          input :attachment, :file, label: "File", readonly: true
          input :clip, :video, label: "Video", disabled: true
        end
      end
    end
  end

  translations do
    context :naming do
      translate :singular, t("inline row")
      translate :plural, t("inline rows")
    end
  end
end

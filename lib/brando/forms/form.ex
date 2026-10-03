defmodule Brando.Forms.Form do
  @moduledoc """
  A form visitors fill in on the site — a contact or signup form — built in
  the admin from `Brando.Forms.Field`s.

  Each language has its own form, linked to the others as a synchronized
  translation: the source decides which fields there are, their keys, types,
  layout and option values; a translation words them in its own language. A
  form is addressed by `key`, which is the same in every language.
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Forms",
    schema: "Form",
    singular: "form",
    plural: "forms",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext

  import Brando.Blueprint.Listings.Components.Core

  alias Brando.Forms.Field

  trait :creator
  trait :timestamped
  trait :status

  trait :translatable,
    mode: :synchronized,
    source_controlled_fields: [
      :key,
      fields: [:key, :type, :required, :width, :new_row, :option_values]
    ]

  trait Brando.Forms.Form.Validate

  identifier false
  persist_identifier false

  attributes do
    attribute :title, :string, required: true
    attribute :key, :string, required: true, unique: [prevent_collision: :language]
    attribute :intro, :text
    attribute :submit_label, :string
    attribute :success_message, :text
  end

  relations do
    relation :fields, :has_many,
      module: Field,
      cast: true,
      drop_param: :drop_fields_ids,
      sort_param: :sort_fields_ids,
      on_replace: :delete,
      preload_order: [asc: :sequence]
  end

  translations do
    context :naming do
      translate :singular, t("form")
      translate :plural, t("forms")
    end
  end

  forms do
    form do
      query %{preload: [:fields, :alternate_entries]}
      default_params %{"status" => "draft"}

      tab t("Form") do
        fieldset do
          size :full
          component &__MODULE__.submissions_link/1
        end

        fieldset do
          style :inline
          input :title, :text, label: t("Title")
          input :key, :text, monospace: true, label: t("Key")
        end

        fieldset do
          style :inline

          input :status, :select,
            label: t("Status"),
            inline: true,
            options: [
              %{value: :draft, label: t("Draft")},
              %{value: :pending, label: t("Pending")},
              %{value: :published, label: t("Published")},
              %{value: :disabled, label: t("Deactivated")}
            ]

          input :language, :select,
            options: :languages,
            narrow: true,
            label: t("Language"),
            hidden: &Brando.I18n.SingleLanguage.single_language?/1
        end

        fieldset do
          size :full

          inputs_for :fields do
            label t("Fields")
            cardinality :many
            component :form_fields

            input :key, :text, label: t("Key", Field)
            input :type, :select, label: t("Type", Field), options: []
            input :label, :text, label: t("Label", Field)
            input :placeholder, :text, label: t("Placeholder", Field)
            input :help_text, :textarea, label: t("Help text", Field)
            input :default_value, :text, label: t("Default value", Field)
            input :required, :toggle, label: t("Required", Field)
            input :width, :select, label: t("Width", Field), options: []
            input :new_row, :toggle, label: t("New row", Field)
            input :option_values, :hidden
          end
        end
      end

      tab t("Messages") do
        fieldset do
          size :half
          input :intro, :textarea, label: t("Introduction"), instructions: t("Shown above the fields.")

          input :submit_label, :text,
            label: t("Submit button"),
            instructions: t("Leave empty to use the site's wording, set under Forms → Messages.")

          input :success_message, :textarea,
            label: t("Success message"),
            instructions:
              t(
                "Shown in place of the form once it has been sent. Leave empty to use the site's wording, set under Forms → Messages."
              )
        end
      end
    end
  end

  # Rendered with every validate of the form, so it links without counting.
  def submissions_link(assigns) do
    assigns = assign(assigns, :key, assigns.form.source.data.key)

    ~H"""
    <div :if={@form.source.data.id} class="form-submissions-link">
      <span>{gettext("What visitors have sent with this form, in every language.")}</span>
      <.link navigate={"/admin/forms/#{@key}/submissions"} class="workspace-button">{gettext("Submissions")}</.link>
    </div>
    """
  end

  listings do
    listing do
      query %{order: [{:asc, :title}], preload: [:fields]}
      filter label: t("Title"), key: "title"
      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.update_link class="listing-title" entry={@entry} columns={10}>
      {@entry.title}
      <:outside>
        <br />
        <small class="monospace">
          {@entry.key} · {ngettext("1 field", "%{count} fields", Enum.count(@entry.fields, &Field.input?/1))}
        </small>
      </:outside>
    </.update_link>
    """
  end
end

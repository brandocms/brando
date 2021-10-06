defmodule Brando.Sites.GlobalSet do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "GlobalSet",
    singular: "global_set",
    plural: "global_sets",
    gettext_module: Brando.Gettext

  import Brando.Gettext
  alias Brando.Content.Var

  trait Brando.Trait.Creator
  trait Brando.Trait.CastPolymorphicEmbeds
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  identifier "{{ entry.label }}"

  attributes do
    attribute :label, :string, required: true
    attribute :key, :string, unique: [prevent_collision: :language], required: true

    attribute :globals, {:array, PolymorphicEmbed},
      types: [
        boolean: Var.Boolean,
        text: Var.Text,
        string: Var.String,
        datetime: Var.Datetime,
        html: Var.Html,
        color: Var.Color
      ],
      type_field: :type,
      on_type_not_found: :raise,
      on_replace: :delete
  end

  forms do
    form do
      tab gettext("Content") do
        fieldset size: :half do
          input :language, :select, options: :languages, narrow: true
          input :label, :text
          input :key, :text, monospace: true
        end

        fieldset size: :full do
          inputs_for :globals, {:component, BrandoAdmin.Components.Form.Input.Globals}
        end
      end
    end
  end

  listings do
    listing do
      listing_query %{
        order: [{:asc, :label}, {:desc, :inserted_at}]
      }

      filters([
        [label: gettext("Label"), filter: "label"]
      ])

      actions([
        [label: gettext("Edit set"), event: "edit_entry"],
        [
          label: gettext("Delete set"),
          event: "delete_entry",
          confirm: gettext("Are you sure?")
        ],
        [label: gettext("Duplicate set"), event: "duplicate_entry"]
      ])

      template(
        """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm-2.29-2.333A17.9 17.9 0 0 1 8.027 13H4.062a8.008 8.008 0 0 0 5.648 6.667zM10.03 13c.151 2.439.848 4.73 1.97 6.752A15.905 15.905 0 0 0 13.97 13h-3.94zm9.908 0h-3.965a17.9 17.9 0 0 1-1.683 6.667A8.008 8.008 0 0 0 19.938 13zM4.062 11h3.965A17.9 17.9 0 0 1 9.71 4.333 8.008 8.008 0 0 0 4.062 11zm5.969 0h3.938A15.905 15.905 0 0 0 12 4.248 15.905 15.905 0 0 0 10.03 11zm4.259-6.667A17.9 17.9 0 0 1 15.973 11h3.965a8.008 8.008 0 0 0-5.648-6.667z"/></svg>
        """,
        columns: 1
      )

      template(
        """
        <a
          data-phx-link="redirect"
          data-phx-link-state="push"
          href="/admin/config/global_sets/update/{{ entry.id }}"
          class="entry-link">
          <div class="monospace small">{{ entry.key }}</div>
          {{ entry.label }}
        </a>
        """,
        columns: 7
      )

      template(
        """
        <small>{{ entry.globals | size }} #{gettext("variables in set")}</small>
        """,
        columns: 3
      )
    end
  end

  translations do
    context :naming do
      translate :singular, t("global set")
      translate :plural, t("global sets")
    end
  end
end

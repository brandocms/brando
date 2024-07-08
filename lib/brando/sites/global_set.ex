defmodule Brando.Sites.GlobalSet do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "GlobalSet",
    singular: "global_set",
    plural: "global_sets",
    gettext_module: Brando.Gettext

  import Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.CastPolymorphicEmbeds
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable, alternates: false

  identifier false
  persist_identifier false

  attributes do
    attribute :label, :string, required: true
    attribute :key, :string, unique: [prevent_collision: :language], required: true
  end

  relations do
    relation :vars, :has_many,
      module: Brando.Content.Var,
      on_replace: :delete_if_exists,
      cast: true,
      sort_param: :sort_var_ids,
      drop_param: :drop_var_ids,
      preload_order: [asc: :sequence]
  end

  forms do
    form do
      tab t("Content") do
        fieldset size: :half do
          input :language, :select, options: :languages, narrow: true, label: t("Language")
          input :label, :text, label: t("Label")
          input :key, :text, monospace: true, label: t("Key")
        end

        fieldset size: :full do
          inputs_for :vars, {:component, BrandoAdmin.Components.Form.Input.Vars},
            label: t("Globals")
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
        [label: t("Label"), filter: "label"]
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
        <small>{{ entry.vars | size }} #{t("variables in set")}</small>
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

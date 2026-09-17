defmodule Brando.Sites.GlobalSet do
  @moduledoc """
  A translatable, named collection of global content variables.

  Global sets expose reusable values to templates without tying them to a
  specific page or content entry.
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "GlobalSet",
    singular: "global_set",
    plural: "global_sets",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext
  import Brando.Blueprint.Listings.Components.Core

  trait :creator
  trait :cast_polymorphic_embeds
  trait :timestamped
  trait :translatable, alternates: false

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
        fieldset do
          size :half
          input :language, :select, options: :languages, narrow: true, label: t("Language")
          input :label, :text, label: t("Label")
          input :key, :text, monospace: true, label: t("Key")
        end

        fieldset do
          inputs_for :vars do
            label t("Globals")
            component :vars
          end
        end
      end
    end
  end

  listings do
    listing do
      query %{order: [{:asc, :label}, {:desc, :inserted_at}]}
      filter label: t("Label"), key: "label"
      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.update_link entry={@entry} columns={8}>
      <span class="global-set-title"><span class="global-set-icon"><Brando.HTML.Icon.icon name="hero-globe-alt" /></span><span class="global-set-text"><span class="global-set-name">{@entry.label}</span><small class="global-set-key monospace">{@entry.key}</small></span></span>
    </.update_link>
    <.field columns={3}>
      <span class="workspace-badge">{ngettext("%{count} variable", "%{count} variables", Enum.count(@entry.vars))}</span>
    </.field>
    """
  end

  translations do
    context :naming do
      translate :singular, t("global set")
      translate :plural, t("global sets")
    end
  end
end

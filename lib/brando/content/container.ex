defmodule Brando.Content.Container do
  @moduledoc """
  Ecto schema for the Villain Content Container schema

  A container can hold multiple blocks
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "Container",
    singular: "container",
    plural: "containers",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext

  identifier "[{{ entry.namespace }}] {{ entry.name}}"
  persist_identifier false

  @derived_fields ~w(id type name sequence namespace help_text code deleted_at)a
  @derive {Jason.Encoder, only: @derived_fields}

  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped

  attributes do
    attribute :type, :enum, values: [:liquid, :heex], default: :liquid
    attribute :name, :string, required: true
    attribute :namespace, :string, required: true
    attribute :help_text, :text
    attribute :code, :text, required: true
    attribute :allow_custom_palette, :boolean, default: false
    attribute :palette_namespace, :string
  end

  relations do
    relation :palette, :belongs_to, module: Brando.Content.Palette
  end

  forms do
    form do
      default_params %{"status" => "draft"}

      tab t("Content") do
        fieldset do
          size :half

          input :type, :select,
            options: [
              %{label: "Liquid", value: :liquid},
              %{label: "Heex", value: :heex}
            ],
            label: t("Type")

          input :name, :text, monospace: true, label: t("Name")
          input :namespace, :text, monospace: true, label: t("Namespace")
          input :allow_custom_palette, :toggle, label: t("Allow custom palette")
          input :palette_namespace, :text, label: t("Palette namespace")

          input :palette_id, :select,
            options: &__MODULE__.get_palettes/2,
            update_relation: {:palette, &__MODULE__.get_palette/1},
            resetable: true,
            label: t("Palette")
        end

        fieldset do
          input :code, :code,
            label: t("Wrapper code"),
            instructions: t("Use `{{ content }}` to render inner content")
        end
      end
    end
  end

  def get_palettes(_, _) do
    available_palettes =
      Brando.Content.list_palettes!(%{status: :published})

    Enum.map(available_palettes, fn palette ->
      colors =
        Enum.map(Enum.reverse(palette.colors), fn color ->
          """
          <span
            class="circle tiny"
            style="background-color:#{color.hex_value}"></span>
          """
        end)

      label = """
      <div class="circle-stack mr-1">
        #{colors}
      </div><span class="text-mono">[#{palette.namespace}] #{palette.name}</span>
      """

      %{label: label, value: palette.id}
    end)
  end

  def get_palette(id) do
    Brando.Content.get_palette!(id)
  end

  listings do
    listing do
      query %{order: [{:asc, :sequence}, {:desc, :inserted_at}]}
      filter label: gettext("Title"), filter: "title"
      filter label: gettext("Namespace"), filter: "namespace"
      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <div class="col-2">
      <div class="badge">
        {@entry.namespace}
      </div>
    </div>
    <.update_link entry={@entry} columns={12}>
      {@entry.name}
    </.update_link>
    """
  end

  translations do
    context :naming do
      translate :singular, t("container")
      translate :plural, t("containers")
    end
  end
end

defmodule Brando.LivePreview.Target do
  @moduledoc false
  defstruct __identifier__: nil,
            __spark_metadata__: nil,
            schema: nil,
            name: :default,
            label: nil,
            description: nil,
            layout: nil,
            template: nil,
            mutate_data: nil,
            rerender_on_change: [],
            reassign_on_change: [],
            schema_preloads: [],
            template_prop: nil,
            template_section: nil,
            template_css_classes: nil,
            assigns: []

  @schema [
    schema: [
      type: :atom,
      required: true,
      doc: "Schema to LivePreview"
    ],
    name: [
      type: :atom,
      default: :default,
      doc: "Stable name, unique within this schema. Existing unnamed targets use :default."
    ],
    label: [type: :string, doc: "Editor-facing name shown in the preview chooser"],
    description: [type: :string, doc: "Optional explanation of this view"],
    layout: [
      type: {:or, [{:tuple, [:atom, {:or, [:string, :atom]}]}, {:fun, 1}]},
      required: false,
      doc: "Layout"
    ],
    template: [
      type: {:or, [{:tuple, [:atom, {:or, [:string, :atom]}]}, {:fun, 1}]},
      required: false,
      doc: "Template"
    ],
    template_section: [
      type: {:or, [:string, {:fun, 1}]},
      required: false,
      doc: "Template section"
    ],
    template_prop: [
      type: :atom,
      required: false,
      doc: "Template prop",
      default: :entry
    ],
    template_css_classes: [
      type: {:or, [:string, {:fun, 1}]},
      required: false,
      doc: "Template CSS classes"
    ],
    mutate_data: [
      type: {:fun, 1},
      required: false,
      doc: "Mutate data"
    ],
    rerender_on_change: [
      type: {:list, :any},
      required: false,
      default: [],
      doc: "Rerender on change"
    ],
    reassign_on_change: [
      type: {:list, :any},
      required: false,
      default: [],
      doc: "Reassign on change"
    ],
    schema_preloads: [
      type: {:list, :any},
      required: false,
      default: [],
      doc: "Preloads passed to `Repo.preload/2`. Accepts nested preloads, e.g. `[related_cases: :identifier]`"
    ],
    assigns: [
      type: {:list, {:tuple, [:atom, {:or, [{:fun, 1}, {:fun, 2}]}]}},
      required: false,
      default: [],
      doc: "Assigns"
    ]
  ]

  def schema, do: @schema

  def transform(%{name: name} = target) when name not in [nil, true, false] do
    label = target.label || if(name == :default, do: "Preview", else: Phoenix.Naming.humanize(name))
    {:ok, %{target | label: label}}
  end

  def transform(_target), do: {:error, "preview target name must be a non-nil atom other than true or false"}
end

defmodule Brando.LivePreview.Target do
  @moduledoc false
  defstruct __identifier__: nil,
            schema: nil,
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
      type: {:list, :atom},
      required: false,
      default: [],
      doc: "Preloads"
    ],
    assigns: [
      type: {:list, {:tuple, [:atom, {:or, [{:fun, 1}, {:fun, 2}]}]}},
      required: false,
      default: [],
      doc: "Assigns"
    ]
  ]

  def schema, do: @schema
end

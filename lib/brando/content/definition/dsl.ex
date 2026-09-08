defmodule Brando.Content.Definition.Dsl do
  @moduledoc false

  defmodule Ref do
    @moduledoc false
    defstruct [
      :name,
      :type,
      :uid,
      :description,
      :__spark_metadata__,
      active: true,
      collapsed: false,
      config: [],
      default: [],
      assets: []
    ]
  end

  defmodule Var do
    @moduledoc false
    defstruct [
      :key,
      :type,
      :__spark_metadata__,
      label: :__unset__,
      placeholder: :__unset__,
      instructions: :__unset__,
      width: :__unset__,
      placement: :__unset__,
      new_row: :__unset__,
      options: :__unset__,
      default: :__unset__,
      settings: [],
      assets: []
    ]
  end

  defmodule Template do
    @moduledoc false
    defstruct [:engine, :source, :__spark_metadata__, file: false]
  end

  defmodule Child do
    @moduledoc false
    defstruct [:definition, :__spark_metadata__]
  end

  @options [
    kind: [type: {:in, [:module, :table_template]}, default: :module],
    uid: [type: :string, required: true],
    name: [type: :any, required: true],
    namespace: [type: :any],
    help_text: [type: :any],
    class: [type: :string],
    svg: [type: :any],
    color: [type: :any],
    multi: [type: :any],
    sequence: [type: :any],
    datasource: [type: :any],
    datasource_module: [type: :any],
    datasource_type: [type: :any],
    datasource_query: [type: :any],
    table_template: [type: :any]
  ]

  @ref_schema [
    name: [type: {:or, [:atom, :string]}, required: true],
    type: [type: {:or, [:atom, :string]}, required: true],
    uid: [type: :string],
    description: [type: :any],
    active: [type: :boolean, default: true],
    collapsed: [type: :boolean, default: false],
    config: [type: :any, default: []],
    default: [type: :any, default: []],
    assets: [type: :any, default: []]
  ]

  @var_schema [
    key: [type: {:or, [:atom, :string]}, required: true],
    type: [type: {:or, [:atom, :string]}, required: true],
    label: [type: :any, default: :__unset__],
    placeholder: [type: :any, default: :__unset__],
    instructions: [type: :any, default: :__unset__],
    width: [type: :any, default: :__unset__],
    placement: [type: :any, default: :__unset__],
    new_row: [type: :any, default: :__unset__],
    options: [type: :any, default: :__unset__],
    default: [type: :any, default: :__unset__],
    settings: [type: :any, default: []],
    assets: [type: :any, default: []]
  ]

  @template_schema [
    engine: [type: {:in, [:heex, :liquid]}, required: true],
    source: [type: :string, required: true]
  ]

  @root %Spark.Dsl.Section{
    name: :definition,
    top_level?: true,
    schema: @options,
    entities: [
      %Spark.Dsl.Entity{name: :template, args: [:engine, :source], target: Template, schema: @template_schema},
      %Spark.Dsl.Entity{
        name: :template_file,
        args: [:engine, :source],
        target: Template,
        schema: @template_schema,
        auto_set_fields: [file: true]
      }
    ]
  }

  @refs %Spark.Dsl.Section{
    name: :refs,
    entities: [%Spark.Dsl.Entity{name: :ref, args: [:name, :type], target: Ref, schema: @ref_schema}]
  }

  @vars %Spark.Dsl.Section{
    name: :vars,
    entities: [%Spark.Dsl.Entity{name: :var, args: [:key, :type], target: Var, schema: @var_schema}]
  }

  @children %Spark.Dsl.Section{
    name: :children,
    entities: [
      %Spark.Dsl.Entity{
        name: :child,
        args: [:definition],
        target: Child,
        schema: [definition: [type: {:or, [:atom, :string]}, required: true]]
      }
    ]
  }

  use Spark.Dsl.Extension, sections: [@root, @refs, @vars, @children]

  def options, do: @options
  def ref_schema, do: @ref_schema
  def var_schema, do: @var_schema
end

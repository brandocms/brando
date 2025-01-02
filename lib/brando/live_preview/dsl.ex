defmodule Brando.LivePreview.Dsl do
  @assign %Spark.Dsl.Entity{
    name: :assign,
    args: [:key, :value_fn],
    target: Brando.LivePreview.Target.Assign,
    schema: Brando.LivePreview.Target.Assign.schema()
  }

  @preview_target %Spark.Dsl.Entity{
    name: :preview_target,
    identifier: :schema,
    args: [:schema],
    entities: [assigns: [@assign]],
    target: Brando.LivePreview.Target,
    schema: Brando.LivePreview.Target.schema()
  }

  @root %Spark.Dsl.Section{
    name: :live_preview,
    entities: [@preview_target],
    top_level?: true
  }

  @sections [@root]

  @moduledoc false
  use Spark.Dsl.Extension,
    sections: @sections,
    transformers: [],
    imports: [Brando.LivePreview.Legacy]
end

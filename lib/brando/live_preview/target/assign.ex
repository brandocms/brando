defmodule Brando.LivePreview.Target.Assign do
  @moduledoc false
  defstruct __spark_metadata__: nil,
            key: nil,
            value_fn: nil

  @schema [
    key: [
      type: :atom,
      required: true,
      doc: "Key of assign"
    ],
    value_fn: [
      type: {:or, [{:fun, 1}, {:fun, 2}]},
      required: true,
      doc: "Function to get value. Receives entry and language."
    ]
  ]

  def schema, do: @schema
end

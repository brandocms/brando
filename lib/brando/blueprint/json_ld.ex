defmodule Brando.Blueprint.JSONLD do
  use Spark.Dsl,
    default_extensions: [extensions: [Brando.Blueprint.JSONLD.Dsl]],
    opts_to_document: []
end

defmodule Brando.Blueprint.Dsl do
  use Spark.Dsl,
    default_extensions: [
      extensions: [
        Brando.Blueprint.JSONLD.Dsl,
        Brando.Blueprint.Meta.Dsl,
        Brando.Blueprint.Forms.Dsl,
        Brando.Blueprint.Listings.Dsl
      ]
    ],
    opts_to_document: []
end

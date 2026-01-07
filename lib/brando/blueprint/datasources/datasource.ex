defmodule Brando.Blueprint.Datasources.Datasource do
  @moduledoc false
  defstruct __identifier__: nil,
            __spark_metadata__: nil,
            key: nil,
            type: nil,
            list: nil,
            get: nil,
            meta: []
end

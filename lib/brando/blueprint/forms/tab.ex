defmodule Brando.Blueprint.Forms.Tab do
  @moduledoc false
  # `alerts` is where the DSL puts a tab's `alert` entities; without the
  # field they were silently dropped. They render above the fieldsets.
  defstruct __spark_metadata__: nil,
            name: nil,
            fields: [],
            alerts: []
end

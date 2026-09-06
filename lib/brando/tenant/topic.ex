defmodule Brando.Tenant.Topic do
  @moduledoc "Separates content notifications and collaboration by environment and resource."

  def entry(event, schema, id), do: scoped("brando:#{event}:#{inspect(schema)}:#{id}")

  def scoped(topic) do
    case Brando.Tenant.current_prefix() do
      nil -> topic
      prefix -> topic <> ":tenant:" <> prefix
    end
  end
end

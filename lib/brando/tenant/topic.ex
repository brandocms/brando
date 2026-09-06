defmodule Brando.Tenant.Topic do
  @moduledoc "Separates content notifications and collaboration by environment."

  def scoped(topic) do
    case Brando.Tenant.current_prefix() do
      nil -> topic
      prefix -> topic <> ":tenant:" <> prefix
    end
  end
end

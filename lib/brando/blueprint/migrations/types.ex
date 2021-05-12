defmodule Brando.Blueprint.Migrations.Types do
  def migration_type(:string), do: :text
  def migration_type(:villain), do: :jsonb
  def migration_type(:image), do: :jsonb
  def migration_type(:video), do: :jsonb
  def migration_type(:language), do: :text
  def migration_type(:slug), do: :text
  def migration_type(:status), do: :integer
  def migration_type(:datetime), do: :utc_datetime
  def migration_type(:enum), do: :text
  def migration_type(type), do: type
end

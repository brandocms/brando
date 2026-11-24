# A type besides pages whose unique address is freed in the trash and asked
# back on a restore (#3941), on the E2E project's table, which no other test
# Blueprint uses
defmodule Brando.RestoreTest.Project do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "RestoreTest",
    schema: "Project",
    singular: "project",
    plural: "projects",
    gettext_module: Brando.Gettext

  table "projects_projects"

  trait :creator
  trait :soft_delete, obfuscated_fields: [:slug]
  trait :status
  trait :timestamped

  identifier "{{ entry.title }}"
  persist_identifier false

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true, unique: [prevent_collision: true]
  end

  listings do
    listing do
      query %{order: [{:asc, :id}]}
    end
  end
end

defmodule Brando.RestoreTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.RestoreTest.Project

  query :single, Project, do: fn query -> from(q in query) end
  query :list, Project, do: fn query -> from(q in query) end

  matches Project do
    fn {:id, id}, query -> from t in query, where: t.id == ^id end
  end

  mutation :create, Project
end

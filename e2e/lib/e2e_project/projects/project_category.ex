defmodule E2eProject.Projects.ProjectCategory do
  @moduledoc """
  Blueprint for ProjectCategory
  """

  use Brando.Blueprint,
    application: "E2eProject",
    domain: "Projects",
    schema: "ProjectCategory",
    singular: "project_category",
    plural: "project_categories"

  alias E2eProject.Projects

  trait Brando.Trait.Sequenced

  absolute_url "{% route project_category_path detail { entry.slug } %}"

  @allow_mark_as_deleted true

  relations do
    relation :project, :belongs_to, module: Projects.Project
    relation :category, :belongs_to, module: Projects.Category
  end

  translations do
    context :naming do
      translate :singular, t("project category")
      translate :plural, t("project categories")
    end
  end
end

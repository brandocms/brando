defmodule E2eProjectWeb.API.ProjectView do
  @moduledoc "JSON:API view for projects."
  use BrandoJsonApi.View, schema: E2eProject.Projects.Project
end

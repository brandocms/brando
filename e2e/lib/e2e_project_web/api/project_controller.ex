defmodule E2eProjectWeb.API.ProjectController do
  @moduledoc "JSON:API controller for projects."
  use BrandoJsonApi.Controller,
    schema: E2eProject.Projects.Project,
    view: E2eProjectWeb.API.ProjectView
end

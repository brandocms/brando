defmodule E2eProjectAdmin.Menus do
  use BrandoAdmin.Menu

  menus do
    menu_item E2eProject.Projects.Client
    menu_item E2eProject.Projects.Project
    menu_item E2eProject.Projects.Category
  end
end

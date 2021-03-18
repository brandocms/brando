import Brando.Blueprint

language :en do
  singular "project"
  plural "projects"

  t [:fields, :title, :label], "Title"
  t [:fields, :slug, :label], "Slug"
  t [:fields, :cover, :label], "Cover"
  t [:fields, :cover, :help_text], "Image used in listings"
  t [:fields, :blocks, :label], "Block content"
  t [:fields, :blocks, :help_text], "Leave empty if you don't want to create an article"
end

language :no do
  singular "prosjekt"
  plural "prosjekter"

  t [:fields, :title, :label], "Title"
  t [:fields, :slug, :label], "Slug"
  t [:fields, :cover, :label], "Cover"
  t [:fields, :cover, :help_text], "Image used in listings"
  t [:fields, :blocks, :label], "Block content"
  t [:fields, :blocks, :help_text], "Leave empty if you don't want to create an article"
end

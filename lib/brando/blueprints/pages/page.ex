defmodule Brando.Blueprints.Pages.Page do
  use Brando.Blueprint

  application "Brando"
  # domain "Pages"
  # schema "Page"
  # singular "page"
  # plural "pages"

  # trait :sequence
  # trait :creator
  # trait :meta
  # trait :status
  # trait :soft_delete
  # trait :revisions
end

#   identifier_file = Path.join(:code.priv_dir(:brando), "blueprints/pages/page/identifier.exs")
#   {ret, _} = Code.eval_file(identifier_file)

#   require Logger
#   Logger.error(inspect(ret.(%{name: "Hello hello!"}), pretty: true))

#   blueprint do
#     application "Brando"
#     domain "Pages"
#     schema "Page"
#     singular "page"
#     plural "pages"

#     identifier fn entry -> entry.title end

#     absolute_url fn routes, endpoint, entry ->
#       (entry.uri == "index" && "/") ||
#         routes.page_path(endpoint, :show, String.split(entry.uri, "/"))
#     end

#     # data_schema do
#     #   field :name
#     #   field :email
#     # end

#     # meta_schema do
#     #   field ["description", "og:description"], [:meta_description]
#     #   field ["title", "og:title"], &Brando.Meta.Schema.fallback(&1, [:meta_title, :title])
#     #   field "og:image", [:meta_image]
#     #   field "og:locale", [:language], &Brando.Meta.Utils.encode_locale/1
#     # end
#   end
# end

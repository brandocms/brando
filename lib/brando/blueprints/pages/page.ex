# defmodule Brando.Blueprints.Pages.Page do
#   use Brando.Blueprint
#   import Brando.Gettext
#   alias Brando.Pages

#   # traits do
#   #   trait :meta
#   #   trait :villain
#   #   trait :creator
#   #   trait :scheduled_publishing
#   #   trait :revisioned
#   #   trait :sequenced
#   # end

#   def identifier(entry), do: entry.name

#   def get_absolute_url(routes, endpoint, entry),
#     do: routes.page_path(endpoint, :show, [entry.uri])

#   # def data_layer do
#   #   attributes do
#   #     attribute :title, :string, max_length: 160
#   #     attribute :slug, :slug, from: :title
#   #     attribute :uri, :string
#   #     attribute :language, :string
#   #     attribute :template, :string
#   #     attribute :is_homepage, :boolean
#   #     attribute :status, :status
#   #     attribute :css_classes, :string
#   #     attribute :data, :villain
#   #   end

#   #   relations do
#   #     belongs_to :parent, __MODULE__
#   #     has_many :children, __MODULE__, foreign_key: :parent_id
#   #     has_many :fragments, PageFragment
#   #     has_many :properties, Property, on_replace: :delete
#   #   end
#   # end

# translations do
#   translation :naming do
#     singular gettext("page")
#     plural gettext("pages")
#   end

#   translation :fields do
#     t [:advanced_config] do
#       t :label, gettext("Advanced configuration")
#     end
#   end
# end

#   def translations(:naming) do
#     translation do
#       t [:singular], gettext("page")
#       t [:plural], gettext("pages")
#     end
#   end

#   def translations(:fields) do
#     translation do
#       t [:advanced_config] do
#         t :label, gettext("Advanced configuration")
#       end

#       t [:language] do
#         t :label, gettext("Language")
#       end

#       t [:parent_id] do
#         t :label, gettext("Parent page")
#       end

#       t [:title] do
#         t :label, gettext("Title")
#       end

#       t [:template] do
#         t :label, gettext("Template")
#       end

#       t [:uri] do
#         t :label, gettext("URI")
#         t :placeholder, gettext("uri/goes/here")
#         t :instructions, gettext("Path for routing")
#       end

#       t [:is_homepage] do
#         t :label, gettext("Homepage")
#       end

#       t [:css_classes] do
#         t :label, gettext("Extra CSS classes")
#       end

#       t [:properties] do
#         t :label, gettext("Page properties (advanced)")
#       end

#       t [:data] do
#         t :label, gettext("Contents")
#       end

#       t [:publish_at] do
#         t :label, gettext("Publish at")
#         t :instructions, gettext("Leave blank if you wish to publish immidiately")
#       end
#     end
#   end
# end

defmodule Brando.Blueprints.Users.User do
  use Brando.Blueprint

  blueprint do
    application "Brando"
    domain "Users"
    schema "User"
    singular "user"
    plural "users"

    identifier fn entry -> entry.name end
    absolute_url false

    # data_schema do
    #   field :name
    #   field :email
    # end

    # meta_schema do
    #   field ["description", "og:description"], [:meta_description]
    #   field ["title", "og:title"], &Brando.Meta.Schema.fallback(&1, [:meta_title, :title])
    #   field "og:image", [:meta_image]
    #   field "og:locale", [:language], &Brando.Meta.Utils.encode_locale/1
    # end
  end
end

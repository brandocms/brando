defmodule Brando.Schema.Types.User do
  use Brando.Web, :absinthe

  object :user do
    field :id, :id
    field :email, :string
    field :full_name, :string
    field :password, :string
    field :avatar, :image_type
    field :role, :string
    field :active, :boolean
    field :language, :string
    field :last_login, :date
    field :config, :user_config
    field :inserted_at, :time
    field :updated_at, :time
    field :deleted_at, :time
  end

  object :user_config do
    field :show_onboarding, :boolean
  end

  input_object :user_config_params do
    field :show_onboarding, :boolean
  end

  input_object :user_params do
    field :full_name, :string
    field :language, :string
    field :email, :string
    field :role, :string
    field :password, :string
    field :avatar, :upload_or_image
    field :active, :boolean
    field :config, :user_config_params
  end

  object :user_queries do
    @desc "Get current user"
    field :me, type: :user do
      resolve &Brando.Users.UserResolver.me/2
    end

    @desc "Get all users"
    field :users, type: list_of(:user) do
      resolve &Brando.Users.UserResolver.all/2
    end

    @desc "Get user"
    field :user, type: :user do
      arg :user_id, non_null(:id)
      resolve &Brando.Users.UserResolver.find/2
    end
  end

  object :user_mutations do
    field :create_user, type: :user do
      arg :user_params, :user_params

      resolve &Brando.Users.UserResolver.create/2
    end

    field :update_user, type: :user do
      arg :user_id, non_null(:id)
      arg :user_params, :user_params

      resolve &Brando.Users.UserResolver.update/2
    end
  end
end

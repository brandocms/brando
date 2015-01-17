defmodule <%= application_name %>.Users.Admin.Routes do
  alias Phoenix.Router.Resource

  defmacro users_resources(path, controller, opts, do: nested_context) do
    add_users_resources path, controller, opts, do: nested_context
  end

  defmacro users_resources(path, controller, do: nested_context) do
    add_users_resources path, controller, [], do: nested_context
  end

  defmacro users_resources(path, controller, opts) do
    add_users_resources path, controller, opts, do: nil
  end

  defmacro users_resources(path, controller) do
    add_users_resources path, controller, [], do: nil
  end

  defmacro users_resources(path) do
    add_users_resources path, <%= application_name %>.Users.Admin.UserController, [], do: nil
  end

  defp add_users_resources(path, controller, options, do: context) do
    quote do
      resource = Resource.build(unquote(path), unquote(controller), unquote(options))
      parm = resource.param
      path = resource.path
      ctrl = resource.controller
      opts = [as: resource.as]

      Enum.each resource.actions, fn action ->
        case action do
          :index   -> get    "#{path}",               ctrl, :index, opts
          :show    -> get    "#{path}/:#{parm}",      ctrl, :show, opts
          :new     -> get    "#{path}/ny",           ctrl, :new, opts
          :edit    -> get    "#{path}/:#{parm}/endre", ctrl, :edit, opts
          :create  -> post   "#{path}",               ctrl, :create, opts
          :destroy -> delete "#{path}/:#{parm}",      ctrl, :destroy, opts
          :update  ->
            patch "#{path}/:#{parm}", ctrl, :update, opts
            put   "#{path}/:#{parm}", ctrl, :update, as: nil
        end
      end
      get    "#{path}/profil",      ctrl, :profile, opts
      scope resource.member do
        unquote(context)
      end
    end

  end
end
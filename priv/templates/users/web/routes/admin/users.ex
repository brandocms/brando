defmodule <%= application_name %>.Users.Admin.Routes do
  alias Phoenix.Router.Resource
  #alias Phoenix.Router.Scope

  @doc """
    Defines "RESTful" endpoints for a resource.
    The given definition:
        users_resources "/users"
    will include routes to the following actions:
      * `GET /users` => `:index`
      * `GET /users/new` => `:new`
      * `POST /users` => `:create`
      * `GET /users/:id` => `:show`
      * `GET /users/:id/edit` => `:edit`
      * `PATCH /users/:id` => `:update`
      * `PUT /users/:id` => `:update`
      * `DELETE /users/:id` => `:destroy`
    ## Options
    This macro accepts a set of options:
      * `:only` - a list of actions to generate routes for, for example: `[:show, :edit]`
      * `:except` - a list of actions to exclude generated routes from, for example: `[:destroy]`
      * `:param` - the name of the paramter for this resource, defaults to `"id"`
      * `:name` - the prefix for this resource. This is used for the named helper
        and as the prefix for the parameter in nested resources. The default value
        is automatically derived from the controller name, i.e. `UserController` will
        have name `"user"`
      * `:as` - configures the named helper exclusively
  """

  defmacro users_resources(path, opts) do
    add_users_resources path, Brando.Users.Admin.UserController, opts, do: nil
  end

  defmacro users_resources(path) do
    add_users_resources path, Brando.Users.Admin.UserController, [], do: nil
  end

  defp add_users_resources(path, controller, options, do: context) do
    quote do
      resource = Resource.build(unquote(path), unquote(controller), unquote(options))
      parm = resource.param
      path = resource.path
      ctrl = resource.controller
      opts = resource.route

      Enum.each resource.actions, fn action ->
        case action do
          :index   -> get    "#{path}",               ctrl, :index, opts
          :show    -> get    "#{path}/:#{parm}",      ctrl, :show, opts
          :new     -> get    "#{path}/ny",           ctrl, :new, opts
          :edit    -> get    "#{path}/:#{parm}/endre", ctrl, :edit, opts
          :create  -> post   "#{path}",               ctrl, :create, opts
          :delete  -> delete "#{path}/:#{parm}",      ctrl, :delete, opts
          :update  ->
            patch "#{path}/:#{parm}", ctrl, :update, opts
            put   "#{path}/:#{parm}", ctrl, :update, Keyword.put(opts, :as, nil)
        end
      end
      get    "#{path}/profil",      ctrl, :profile, opts
      scope resource.member do
        unquote(context)
      end
    end

  end
end
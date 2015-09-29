defmodule Mix.Tasks.Brando.Gen.Html do
  use Mix.Task

  @shortdoc "Generates a Brando-styled model"

  @moduledoc """
  Generates a Brando resource.

      mix brando.gen.html User users name:string avatar:image data:villain

  The first argument is the module name followed by
  its plural name (used for resources and schema).

  The generated resource will contain:

    * a model in web/models
    * a view in web/views
    * a controller in web/controllers
    * a migration file for the repository
    * default CRUD templates in web/templates
    * test files for generated model and controller

  The generated model can be skipped with `--no-model`.
  Read the documentation for `phoenix.gen.model` for more
  information on attributes and namespaced resources.
  """
  def run(args) do
    {opts, parsed, _} = OptionParser.parse(args, switches: [model: :boolean])
    [singular, plural | attrs] = validate_args!(parsed)

    no_singular  = opts[:nosingular] || Mix.Shell.IO.prompt("Singular (no): ")
    no_singular  = String.strip(no_singular)
    no_plural    = opts[:noplural] || Mix.Shell.IO.prompt("Plural (no): ")
    no_plural    = String.strip(no_plural)

    attrs        = Mix.Brando.attrs(attrs)
    villain?     = :villain in Dict.values(attrs)
    image_field? = :image in Dict.values(attrs)
    binding      = Mix.Brando.inflect(singular)
    admin_path   = Enum.join(["admin", binding[:path]], "_")
    path         = binding[:path]
    route        = path
                   |> String.split("/") |> Enum.drop(-1)
                   |> Kernel.++([plural]) |> Enum.join("/")
    admin_module = Enum.join([binding[:base], "Admin", binding[:scoped]], ".")
    binding      = binding ++ [plural: plural, route: route, no_plural: no_plural, no_singular: no_singular,
                               image_field: image_field?, villain: villain?,
                               admin_module: admin_module, admin_path: admin_path,
                               inputs: inputs(attrs), params: Mix.Brando.params(attrs)]

    files = [
      {:eex, "admin_controller.ex",
             "web/controllers/admin/#{path}_controller.ex"},
      {:eex, "controller.ex",
             "web/controllers/#{path}_controller.ex"},
      {:eex, "menu.ex",
             "web/menus/admin/#{path}_menu.ex"},
      {:eex, "form.ex",
             "web/forms/admin/#{path}_form.ex"},
      {:eex, "edit.html.eex",
             "web/templates/admin/#{path}/edit.html.eex"},
      {:eex, "admin_index.html.eex",
             "web/templates/admin/#{path}/index.html.eex"},
      {:eex, "index.html.eex",
             "web/templates/#{path}/index.html.eex"},
      {:eex, "new.html.eex",
             "web/templates/admin/#{path}/new.html.eex"},
      {:eex, "show.html.eex",
             "web/templates/admin/#{path}/show.html.eex"},
      {:eex, "delete_confirm.html.eex",
             "web/templates/admin/#{path}/delete_confirm.html.eex"},
      {:eex, "admin_view.ex",
             "web/views/admin/#{path}_view.ex"},
      {:eex, "view.ex",
             "web/views/#{path}_view.ex"},
      {:eex, "admin_controller_test.exs",
             "test/controllers/admin/#{path}_controller_test.exs"},
    ]

    if villain? do
      files = files ++ [
        {:eex, "_scripts.html.eex",
               "web/templates/admin/#{path}/_scripts.new.html.eex"},
        {:eex, "_scripts.html.eex",
               "web/templates/admin/#{path}/_scripts.edit.html.eex"},
        {:eex, "_stylesheets.html.eex",
               "web/templates/admin/#{path}/_stylesheets.new.html.eex"},
        {:eex, "_stylesheets.html.eex",
               "web/templates/admin/#{path}/_stylesheets.edit.html.eex"},
      ]
    end

    Mix.Brando.check_module_name_availability!(binding[:module] <>
                                                "Controller")
    Mix.Brando.check_module_name_availability!(binding[:module] <>
                                                "View")
    Mix.Brando.check_module_name_availability!(binding[:admin_module] <>
                                                "Controller")
    Mix.Brando.check_module_name_availability!(binding[:admin_module] <>
                                                "View")

    Mix.Task.run "brando.gen.model", args ++ ["--nosingular", no_singular,
                                              "--noplural", no_plural]

    Mix.Brando.copy_from(apps(), "priv/templates/brando.gen.html",
                          "", binding, files)

    villain_info =
      if villain? do
        ~s(    villain_routes "/#{route}",    #{binding[:scoped]}Controller)
      else
        ""
      end

    Mix.shell.info """
    Add the resource to your browser scope in web/router.ex by either

        import Brando.Routes.Admin
        admin_routes "#{route}", #{binding[:scoped]}Controller

    or for more fine grained control:

        get    "/#{route}",            #{binding[:scoped]}Controller, :index
        get    "/#{route}/new",        #{binding[:scoped]}Controller, :new
        get    "/#{route}/:id/edit",   #{binding[:scoped]}Controller, :edit
        get    "/#{route}/:id/delete", #{binding[:scoped]}Controller, :delete_confirm
        get    "/#{route}/:id",        #{binding[:scoped]}Controller, :show
        post   "/#{route}",            #{binding[:scoped]}Controller, :create
        delete "/#{route}/:id",        #{binding[:scoped]}Controller, :delete
        patch  "/#{route}/:id",        #{binding[:scoped]}Controller, :update
        put    "/#{route}/:id",        #{binding[:scoped]}Controller, :update

    """ <> villain_info <>
    """

    and then update your repository by running migrations:
        $ mix ecto.migrate

    Install menu by adding to your `config/brando.exs`

        config :brando, Brando.Menu,
          modules: [#{String.capitalize(plural)}, ...]

    """
  end

  defp validate_args!([_, plural | _] = args) do
    if String.contains?(plural, ":") do
      raise_with_help
    else
      args
    end
  end

  defp validate_args!(_) do
    raise_with_help
  end

  defp raise_with_help do
    Mix.raise """
    mix brando.gen.html expects both singular and plural names
    of the generated resource followed by any number of attributes:
        mix brando.gen.html User users name:string avatar:image data:villain
    """
  end

  defp inputs(attrs) do
    Enum.map attrs, fn
      {k, {:array, _}} ->
        {k, nil, nil}
      {k, :boolean}    ->
        {k, ~s(field #{inspect(k)}, :checkbox)}
      {k, :text}       ->
        {k, ~s(field #{inspect(k)}, :textarea, [rows: 4])}
      {k, :date}       ->
        {k, ~s(field #{inspect(k)}, :text, [default: &Brando.Utils.get_now/0])}
      {k, :time}       ->
        {k, ~s(field #{inspect(k)}, :text, [default: &Brando.Utils.get_now/0])}
      {k, :datetime}   ->
        {k, ~s(field #{inspect(k)}, :text, [default: &Brando.Utils.get_now/0])}
      {k, :image}      ->
        {k, ~s(field #{inspect(k)}, :file, [required: false])}
      {k, :villain}      ->
        {k, ~s(field #{inspect(k)}, :textarea)}
      {k, _}           ->
        {k, ~s(field #{inspect(k)}, :text)}
    end
  end

  defp apps do
    [Mix.Project.config[:app], :brando]
  end
end

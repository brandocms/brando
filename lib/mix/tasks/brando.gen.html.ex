defmodule Mix.Tasks.Brando.Gen.Html do
  use Mix.Task

  @shortdoc "Generates a Brando-styled schema"

  @moduledoc """
  Generates a Brando resource.

      mix brando.gen.html User users name:string avatar:image data:villain

  The first argument is the module name followed by
  its plural name (used for resources and schema).

  The generated resource will contain:

    * a schema in web/schemas
    * a view in web/views
    * a controller in web/controllers
    * a migration file for the repository
    * default CRUD templates in web/templates
    * test files for generated schema and controller

  The generated schema can be skipped with `--no-schema`.
  Read the documentation for `phoenix.gen.schema` for more
  information on attributes and namespaced resources.
  """
  def run(args) do



  end

  defp create_domain(domain_name) do
    mkdir_p!("lib/#{domain_name}")
    domain_code = create_schema(domain_name)
  end

  defp create_schema(domain_name, domain_code \\ "", instructions \\ "") do
    Mix.shell.info """
    == Creating schema for #{domain_name}
    """
    singular = Mix.shell.prompt("+ Enter schema name (e.g. Post)")
    plural   = Mix.shell.prompt("+ Enter plural name (e.g. posts)")
    attrs    = Mix.shell.prompt("+ Enter schema fields (e.g. name:string avatar:image data:villain)")

    attrs        = Mix.Brando.attrs(attrs)
    villain?     = :villain in Dict.values(attrs)
    sequenced?   = Mix.shell.yes?("\nMake schema sequenceable?")
    image_field? = :image in Dict.values(attrs)
    binding      = Mix.Brando.inflect(singular)
    admin_path   = Enum.join(["admin", binding[:path]], "_")
    path         = binding[:path]
    route        = path
                   |> String.split("/")
                   |> Enum.drop(-1)
                   |> Kernel.++([plural])
                   |> Enum.join("/")
    admin_module = Enum.join([binding[:base], "Admin", binding[:scoped]], ".")
    binding      = binding ++ [plural: plural,
                               route: route,
                               image_field: image_field?,
                               villain: villain?,
                               sequenced: sequenced?,
                               admin_module: admin_module,
                               admin_path: admin_path,
                               inputs: inputs(attrs),
                               params: Mix.Brando.params(attrs)]

    files = [
      {:eex, "admin_controller.ex",
             "lib/web/controllers/admin/#{path}_controller.ex"},
      {:eex, "controller.ex",
             "lib/web/controllers/#{path}_controller.ex"},
      {:eex, "menu.ex",
             "lib/web/menus/admin/#{path}_menu.ex"},
      {:eex, "form.ex",
             "lib/web/forms/admin/#{path}_form.ex"},
      {:eex, "edit.html.eex",
             "lib/web/templates/admin/#{path}/edit.html.eex"},
      {:eex, "admin_index.html.eex",
             "lib/web/templates/admin/#{path}/index.html.eex"},
      {:eex, "index.html.eex",
             "lib/web/templates/#{path}/index.html.eex"},
      {:eex, "new.html.eex",
             "lib/web/templates/admin/#{path}/new.html.eex"},
      {:eex, "show.html.eex",
             "lib/web/templates/admin/#{path}/show.html.eex"},
      {:eex, "delete_confirm.html.eex",
             "lib/web/templates/admin/#{path}/delete_confirm.html.eex"},
      {:eex, "admin_view.ex",
             "lib/web/views/admin/#{path}_view.ex"},
      {:eex, "view.ex",
             "lib/web/views/#{path}_view.ex"},
      {:eex, "admin_controller_test.exs",
             "test/controllers/admin/#{path}_controller_test.exs"},
    ]

    files =
      if villain? do
        files ++ [
          {:eex, "_scripts.html.eex",
                 "web/templates/admin/#{path}/_scripts.new.html.eex"},
          {:eex, "_scripts.html.eex",
                 "web/templates/admin/#{path}/_scripts.edit.html.eex"},
          {:eex, "_stylesheets.html.eex",
                 "web/templates/admin/#{path}/_stylesheets.new.html.eex"},
          {:eex, "_stylesheets.html.eex",
                 "web/templates/admin/#{path}/_stylesheets.edit.html.eex"},
        ]
      else
        files
      end

    {files, args} =
      if sequenced? do
        files = files ++ [
          {:eex, "sequence.html.eex",
                 "web/templates/admin/#{path}/sequence.html.eex"}]
        {files, args ++ ["--sequenced"]}
      else
        {files, args}
      end

    Mix.Brando.check_module_name_availability!(binding[:module] <> "Web.Controller")
    Mix.Brando.check_module_name_availability!(binding[:module] <> "Web.View")
    Mix.Brando.check_module_name_availability!(binding[:admin_module] <> "Web.Controller")
    Mix.Brando.check_module_name_availability!(binding[:admin_module] <> "Web.View")

    Mix.Task.run "brando.gen.schema", args

    Mix.Brando.copy_from(apps(), "priv/templates/brando.gen.html",
                          "", binding, files)

    villain_info =
      if villain? do
        ~s(    villain_routes "/#{route}",    #{binding[:scoped]}Controller)
      else
        ""
      end

    sequenced_info =
      if sequenced? do
        """
            # insert these two after the first get route
            get    "/#{route}/sort", #{binding[:scoped]}Controller, :sequence
            post   "/#{route}/sort", #{binding[:scoped]}Controller, :sequence_post
        """
      else
        ""
      end

    instructions = instructions <> """
    Add the resource to your browser scope in `lib/web/router.ex`:

        # resources for #{binding[:scoped]}

        import Brando.Villain.Routes.Admin
        alias #{binding[:base]}.Admin.#{binding[:scoped]}Controller

        get    "/#{route}",            #{binding[:scoped]}Controller, :index
        get    "/#{route}/new",        #{binding[:scoped]}Controller, :new
        #{sequenced_info}
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

    Install menu by adding to your supervision tree:

        Brando.Registry.register(#{binding[:base]}.Web.#{binding[:scoped]}, [:menu])

    ================================================================================================
    """

    domain_code = generate_domain_code(domain_code, domain_name, bindings)

    domain_code =
      if Mix.shell.yes?("\nCreate another schema?") do
        create_schema(domain_name, domain_code, instructions)
      else
        {domain_code, instructions}
      end
  end

  defp generate_domain_code(domain_code, domain_name, bindings) do
    domain_code = domain_code <> """
      
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
    # this is for forms

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
    [".", :brando]
  end
end

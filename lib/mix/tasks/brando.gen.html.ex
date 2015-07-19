defmodule Mix.Tasks.Brando.Gen.Html do
  use Mix.Task

  @shortdoc "Generates controller, model and views for an HTML-based resource"

  @moduledoc """
  Generates a Brando resource.
      mix brando.gen.html User users name:string age:integer
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
    {_opts, parsed, _} = OptionParser.parse(args, switches: [model: :boolean])
    [singular, plural | attrs] = validate_args!(parsed)

    image_field? = Mix.shell.yes?("\nInstall image_field in controller?")

    attrs        = Mix.Phoenix.attrs(attrs)
    binding      = Mix.Phoenix.inflect(singular)
    admin_path   = Enum.join(["admin", binding[:path]], "_")
    path         = binding[:path]
    route        = String.split(path, "/") |> Enum.drop(-1) |> Kernel.++([plural]) |> Enum.join("/")
    admin_module = Enum.join([binding[:base], "Admin", binding[:scoped]], ".")
    binding      = binding ++ [plural: plural, route: route,
                               image_field: image_field?,
                               admin_module: admin_module, admin_path: admin_path,
                               inputs: inputs(attrs), params: Mix.Phoenix.params(attrs)]

    Mix.Phoenix.check_module_name_availability!(binding[:module] <> "Controller")
    Mix.Phoenix.check_module_name_availability!(binding[:module] <> "View")
    Mix.Phoenix.check_module_name_availability!(binding[:admin_module] <> "Controller")
    Mix.Phoenix.check_module_name_availability!(binding[:admin_module] <> "View")

    Mix.Task.run "brando.gen.model", args

    Mix.Phoenix.copy_from source_dir, "", binding, [
      {:eex, "admin_controller.ex",       "web/controllers/admin/#{path}_controller.ex"},
      {:eex, "controller.ex",             "web/controllers/#{path}_controller.ex"},
      {:eex, "menu.ex",                   "web/menus/admin/#{path}.ex"},
      {:eex, "form.ex",                   "web/forms/admin/#{path}_form.ex"},
      {:eex, "edit.html.eex",             "web/templates/admin/#{path}/edit.html.eex"},
      {:eex, "admin_index.html.eex",      "web/templates/admin/#{path}/index.html.eex"},
      {:eex, "index.html.eex",            "web/templates/#{path}/index.html.eex"},
      {:eex, "new.html.eex",              "web/templates/admin/#{path}/new.html.eex"},
      {:eex, "show.html.eex",             "web/templates/admin/#{path}/show.html.eex"},
      {:eex, "delete_confirm.html.eex",   "web/templates/admin/#{path}/delete_confirm.html.eex"},
      {:eex, "admin_view.ex",             "web/views/admin/#{path}_view.ex"},
      {:eex, "view.ex",                   "web/views/#{path}_view.ex"},
      {:eex, "admin_controller_test.exs", "test/controllers/admin/#{path}_controller_test.exs"},
    ]

    Mix.shell.info """
    Add the resource to your browser scope in web/router.ex:
        resources "/#{route}", #{binding[:scoped]}Controller
    and then update your repository by running migrations:
        $ mix ecto.migrate

    Install menu by adding to your `config/brando.exs`

        config :brando, Brando.Menu,
          modules: [<%= String.capitalize(plural) %>, ...]

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
        mix brando.gen.html User users name:string avatar:image
    """
  end

  defp inputs(attrs) do
    Enum.map attrs, fn
      {k, {:array, _}} ->
        {k, nil, nil}
      {k, :boolean}    ->
        {k, ~s(field #{inspect(k)}, :checkbox, [required: true, label: "#{String.capitalize(Atom.to_string(k))}"])}
      {k, :text}       ->
        {k, ~s(field #{inspect(k)}, :textarea, [required: true, label: "#{String.capitalize(Atom.to_string(k))}", rows: 4])}
      {k, :date}       ->
        {k, ~s(field #{inspect(k)}, :text, [required: true, label: "#{String.capitalize(Atom.to_string(k))}", default: &Brando.Utils.get_now/0])}
      {k, :time}       ->
        {k, ~s(field #{inspect(k)}, :text, [required: true, label: "#{String.capitalize(Atom.to_string(k))}", default: &Brando.Utils.get_now/0])}
      {k, :datetime}   ->
        {k, ~s(field #{inspect(k)}, :text, [required: true, label: "#{String.capitalize(Atom.to_string(k))}", default: &Brando.Utils.get_now/0])}
      {k, :image}      ->
        {k, ~s(field #{inspect(k)}, :file, [label: "#{String.capitalize(Atom.to_string(k))}"])}
      {k, _}           ->
        {k, ~s(field #{inspect(k)}, :text, [required: true, label: "#{String.capitalize(Atom.to_string(k))}"])}
    end
  end

  defp source_dir do
    Application.app_dir(:brando, "priv/templates/html")
  end
end
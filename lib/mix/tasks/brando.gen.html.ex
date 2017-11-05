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
  def run(_) do
    Mix.shell.info """
    % Brando HTML generator
    -----------------------

    """
    domain = Mix.shell.prompt("+ Enter domain name (e.g. Blog, Accounts, News)") |> String.trim("\n")
    Mix.shell.info """
    == Creating domain for #{domain}
    """
    create_domain(domain)
  end

  defp otp_app do
    Mix.Project.config |> Keyword.fetch!(:app)
  end

  defp create_domain(domain_name) do
    snake_domain =
      domain_name
      |> Phoenix.Naming.underscore
      |> String.split("/")
      |> List.last

    binding = Mix.Brando.inflect(domain_name)

    File.mkdir_p!("lib/#{otp_app()}/#{snake_domain}")
    {domain_code, domain_header, instructions} = create_schema(domain_name)
    File.write!("lib/#{otp_app()}/#{snake_domain}/#{snake_domain}.ex",
    """
    defmodule #{binding[:module]} do
      alias #{binding[:base]}.Repo

      #{domain_header}\n#{domain_code}
    end
    """)

    Mix.shell.info instructions
  end

  defp create_schema(domain_name, domain_header \\ "", domain_code \\ "", instructions \\ "") do
    Mix.shell.info """
    == Schema for #{domain_name}
    """
    singular = Mix.shell.prompt("+ Enter schema name (e.g. Post)") |> String.trim("\n")
    plural   = Mix.shell.prompt("+ Enter plural name (e.g. posts)") |> String.trim("\n")
    attrs    = Mix.shell.prompt("+ Enter schema fields (e.g. name:string avatar:image data:villain)") |> String.trim("\n")

    require Logger

    org_attrs    = attrs |> String.split(" ")
    attrs        = org_attrs |> Mix.Brando.attrs
    villain?     = :villain in Keyword.values(attrs)
    sequenced?   = Mix.shell.yes?("\nMake schema sequenceable?")
    image_field? = :image in Keyword.values(attrs)
    binding      = Mix.Brando.inflect(singular)
    admin_path   = Enum.join(["admin", binding[:path]], "_")
    path         = binding[:path]
    route        = path
                   |> String.split("/")
                   |> Enum.drop(-1)
                   |> Kernel.++([plural])
                   |> Enum.join("/")
    module       = Enum.join([binding[:base] <> "Web", binding[:scoped]], ".")
    admin_module = Enum.join([binding[:base] <> "Web", "Admin", binding[:scoped]], ".")
    binding      = Keyword.delete(binding, :module) ++ [plural: plural,
                               route: route,
                               image_field: image_field?,
                               villain: villain?,
                               sequenced: sequenced?,
                               module: module,
                               admin_module: admin_module,
                               admin_path: admin_path,
                               inputs: inputs(attrs),
                               params: Mix.Brando.params(attrs),
                               domain: domain_name]

    args = [singular, plural, org_attrs]

    files = [
      {:eex, "controller.ex", "lib/application_name_web/controllers/#{path}_controller.ex"},
      {:eex, "index.html.eex", "lib/application_name_web/templates/#{path}/index.html.eex"},
      {:eex, "view.ex", "lib/application_name_web/views/#{path}_view.ex"}
    ]

    {files, args} =
      if sequenced? do
        {files, args ++ ["--sequenced"]}
      else
        {files, args}
      end

    Mix.Brando.check_module_name_availability!(binding[:module] <> "Controller")
    Mix.Brando.check_module_name_availability!(binding[:module] <> "View")

    schema_binding = Mix.Tasks.Brando.Gen.Schema.run(args, domain_name)

    Mix.Brando.copy_from(apps(), "priv/templates/brando.gen.html", "", binding, files)

    sequenced_info =
      if sequenced? do
        """
            get    "/#{route}/sort", #{binding[:scoped]}Controller, :sequence
            post   "/#{route}/sort", #{binding[:scoped]}Controller, :sequence_post
        """
      else
        ""
      end

    instructions = instructions <> """
    Add the resource to your browser scope in `lib/app_name_web/router.ex`:

        # resources for #{binding[:scoped]}
        alias #{binding[:base]}.Web.Admin.#{binding[:scoped]}Controller

        #{sequenced_info}

    and then update your repository by running migrations:
        $ mix ecto.migrate

    ================================================================================================
    """

    domain_header = domain_header <> "\n  alias #{binding[:base]}.#{binding[:domain]}.#{binding[:scoped]}"
    domain_code   = generate_domain_code(domain_code, domain_name, binding, schema_binding)

    if Mix.shell.yes?("\nCreate another schema?") do
      create_schema(domain_name, domain_header, domain_code, instructions)
    else
      {domain_code, domain_header, instructions}
    end
  end

  defp generate_domain_code(domain_code, _, binding, schema_binding) do
    insert_code =
      if schema_binding[:img_fields] do
        optimizers =
          Enum.map(schema_binding[:img_fields],
                   &("Brando.Images.Optimize.optimize(#{binding[:singular]}, :#{elem(&1, 1)})\n"))

        "case Repo.insert(changeset) do\n" <>
        "      {:ok, #{binding[:singular]}} ->\n" <>
        "        #{optimizers}" <>
        "        {:ok, #{binding[:singular]}}\n" <>
        "      {:error, errors} ->\n" <>
        "        {:error, errors}\n" <>
        "    end"
      else
        "Repo.insert(changeset)"
      end
    domain_code <> """

      def list_#{binding[:plural]} do
        Repo.all(#{binding[:alias]})
      end

      def get_#{binding[:singular]}(id) do
        case Repo.get(#{binding[:alias]}, id) do
          nil -> {:error, {:#{binding[:singular]}, :not_found}}
          #{binding[:singular]} -> {:ok, #{binding[:singular]}}
        end
      end

      def create_#{binding[:singular]}(#{binding[:singular]}_params) do
        changeset = #{binding[:alias]}.changeset(%#{binding[:alias]}{}, #{binding[:singular]}_params)
        #{insert_code}
      end

      def update_#{binding[:singular]}(#{binding[:singular]}, #{binding[:singular]}_params) do
        changeset = #{binding[:alias]}.changeset(#{binding[:singular]}, #{binding[:singular]}_params)

        Repo.update(changeset)
      end

      def delete(id) do
        {:ok, #{binding[:singular]}} = get_#{binding[:singular]}(id)
        Repo.delete(#{binding[:singular]})
        {:ok, #{binding[:singular]}}
      end
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

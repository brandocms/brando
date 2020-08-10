defmodule Mix.Tasks.Brando.Gen do
  use Mix.Task

  @shortdoc "Generates a Brando-styled schema"

  @generator_modules [
    Brando.Generators.Schema,
    Brando.Generators.Migration,
    Brando.Generators.Domain,
    Brando.Generators.Vue,
    Brando.Generators.Cypress,
    Brando.Generators.GraphQL
  ]

  @moduledoc """
  Generates a Brando resource.

      mix brando.gen

  """
  @spec run(any) :: no_return
  def run(_) do
    Mix.shell().info("""
    % Brando HTML generator
    -----------------------

    """)

    domain =
      Mix.shell().prompt("+ Enter domain name (e.g. Blog, Accounts, News)") |> String.trim("\n")

    create_schema(domain)
  end

  defp otp_app, do: Mix.Project.config() |> Keyword.fetch!(:app)

  @spec create_schema(any) :: no_return
  defp create_schema(domain_name) do
    Mix.shell().info("""
    == Schema for #{domain_name}
    """)

    snake_domain =
      domain_name
      |> Phoenix.Naming.underscore()
      |> String.split("/")
      |> List.last()

    domain_filename = "lib/#{otp_app()}/#{snake_domain}/#{snake_domain}.ex"
    domain_exists? = File.exists?(domain_filename)

    singular = Mix.shell().prompt("+ Enter schema name (e.g. Post)") |> String.trim("\n")
    plural = Mix.shell().prompt("+ Enter plural name (e.g. posts)") |> String.trim("\n")

    attrs =
      Mix.shell().prompt("""
      + Enter schema fields:

        ## Example

        name:string slug:slug:name status:status meta_description:text avatar:image data:villain image_series:gallery user:references:users

      """)
      |> String.trim("\n")

    org_attrs = attrs |> String.split(" ")
    attrs = org_attrs |> Mix.Brando.attrs()
    main_field = attrs |> List.first() |> elem(0)

    villain? = :villain in Keyword.values(attrs)
    sequenced? = Mix.shell().yes?("\nMake schema sequenceable?")
    soft_delete? = Mix.shell().yes?("\nAdd soft deletion?")
    creator? = Mix.shell().yes?("\nAdd creator?")
    image_field? = :image in Keyword.values(attrs)
    gallery? = :gallery in Keyword.values(attrs)
    status? = :status in Keyword.values(attrs)
    slug? = Keyword.has_key?(Keyword.values(attrs), :slug)

    binding = Mix.Brando.inflect(singular)
    path = binding[:path]
    migration = String.replace(path, "/", "_")

    img_fields =
      attrs
      |> Enum.map(fn {k, v} -> {v, k} end)
      |> Enum.filter(fn {k, _} -> k == :image end)

    file_fields =
      attrs
      |> Enum.map(fn {k, v} -> {v, k} end)
      |> Enum.filter(fn {k, _} -> k == :file end)

    villain_fields =
      attrs
      |> Enum.map(fn {k, v} -> {v, k} end)
      |> Enum.filter(fn {k, _} -> k == :villain end)

    gallery_fields =
      attrs
      |> Enum.map(fn {k, v} -> {v, k} end)
      |> Enum.filter(fn {k, _} -> k == :gallery end)

    route =
      path
      |> String.split("/")
      |> Enum.drop(-1)
      |> Kernel.++([plural])
      |> Enum.join("/")

    module = Enum.join([binding[:base] <> "Web", binding[:scoped]], ".")
    schema_module = Enum.join([binding[:base], domain_name, binding[:scoped]], ".")

    vue_plural = Recase.to_camel(plural)
    vue_singular = Recase.to_camel(singular)

    # schema
    {attrs, assocs} = partition_attrs_and_assocs(attrs)
    migration_types = Enum.map(attrs, &migration_type/1)
    types = types(attrs)
    defs = defaults(attrs)
    params = Mix.Brando.params(attrs)

    binding =
      Keyword.delete(binding, :module) ++
        [
          attrs: attrs,
          assocs: assocs,
          domain_filename: domain_filename,
          plural: plural,
          route: route,
          image_field: image_field?,
          villain: villain?,
          gallery: gallery?,
          status: status?,
          slug: slug?,
          sequenced: sequenced?,
          soft_delete: soft_delete?,
          creator: creator?,
          img_fields: img_fields,
          file_fields: file_fields,
          villain_fields: villain_fields,
          gallery_fields: gallery_fields,
          module: module,
          schema_module: schema_module,
          params: Mix.Brando.params(attrs),
          snake_domain: snake_domain,
          domain: domain_name,
          main_field: main_field,
          types: types,
          migration_types: migration_types,
          defaults: defs,
          params: params,
          vue_singular: Recase.to_camel(binding[:singular]),
          vue_plural: Recase.to_camel(vue_plural)
        ]

    binding = Enum.reduce(@generator_modules, binding, &apply(&1, :before_copy, [&2]))

    migration_path = "priv/repo/migrations/" <> "#{timestamp()}_create_#{migration}.exs"
    schema_path = "lib/application_name/#{snake_domain}/#{path}.ex"
    schema_test_path = "test/schemas/#{path}_test.exs"

    files =
      (domain_exists? && []) ||
        [{:eex, "domain.ex", "lib/application_name/#{snake_domain}/#{snake_domain}.ex"}]

    files =
      files ++
        [
          {:eex, "controller.ex", "lib/application_name_web/controllers/#{path}_controller.ex"},
          {:eex, "list.html.eex", "lib/application_name_web/templates/#{path}/list.html.eex"},
          {:eex, "detail.html.eex", "lib/application_name_web/templates/#{path}/detail.html.eex"},
          {:eex, "__entry.html.eex",
           "lib/application_name_web/templates/#{path}/__#{binding[:singular]}.html.eex"},
          {:eex, "view.ex", "lib/application_name_web/views/#{path}_view.ex"},

          # DB
          {:eex, "migration.exs", migration_path},
          {:eex, "schema.ex", schema_path},
          {:eex, "schema_test.exs", schema_test_path},

          # GQL
          {:eex, "graphql/schema/types/type.ex",
           "lib/application_name/graphql/schema/types/#{path}.ex"},
          {:eex, "graphql/resolvers/resolver.ex",
           "lib/application_name/graphql/resolvers/#{path}_resolver.ex"},

          # Backend JS
          {:eex, "assets/backend/src/api/graphql/ALL_QUERY.graphql",
           "assets/backend/src/gql/#{snake_domain}/#{
             singular |> Inflex.underscore() |> Inflex.pluralize() |> String.upcase()
           }_QUERY.graphql"},
          {:eex, "assets/backend/src/api/graphql/SINGLE_QUERY.graphql",
           "assets/backend/src/gql/#{snake_domain}/#{
             singular |> Inflex.underscore() |> String.upcase()
           }_QUERY.graphql"},
          {:eex, "assets/backend/src/api/graphql/FRAGMENT.graphql",
           "assets/backend/src/gql/#{snake_domain}/#{
             singular |> Inflex.underscore() |> String.upcase()
           }_FRAGMENT.graphql"},
          {:eex, "assets/backend/src/api/graphql/CREATE_MUTATION.graphql",
           "assets/backend/src/gql/#{snake_domain}/CREATE_#{
             singular |> Inflex.underscore() |> String.upcase()
           }_MUTATION.graphql"},
          {:eex, "assets/backend/src/api/graphql/UPDATE_MUTATION.graphql",
           "assets/backend/src/gql/#{snake_domain}/UPDATE_#{
             singular |> Inflex.underscore() |> String.upcase()
           }_MUTATION.graphql"},
          {:eex, "assets/backend/src/api/graphql/DELETE_MUTATION.graphql",
           "assets/backend/src/gql/#{snake_domain}/DELETE_#{
             singular |> Inflex.underscore() |> String.upcase()
           }_MUTATION.graphql"},
          {:eex, "assets/backend/src/menus/menu.js", "assets/backend/src/menus/#{vue_plural}.js"},
          {:eex, "assets/backend/src/routes/route.js",
           "assets/backend/src/routes/#{vue_plural}.js"},
          {:eex, "assets/backend/src/views/List.vue",
           "assets/backend/src/views/#{snake_domain}/#{Recase.to_pascal(vue_singular)}ListView.vue"},
          {:eex_trim, "assets/backend/src/views/Create.vue",
           "assets/backend/src/views/#{snake_domain}/#{Recase.to_pascal(vue_singular)}CreateView.vue"},
          {:eex_trim, "assets/backend/src/views/Edit.vue",
           "assets/backend/src/views/#{snake_domain}/#{Recase.to_pascal(vue_singular)}EditView.vue"},
          {:eex, "assets/backend/src/views/Form.vue",
           "assets/backend/src/views/#{snake_domain}/#{Recase.to_pascal(vue_singular)}Form.vue"},
          {:eex, "assets/backend/src/locale.js",
           "assets/backend/src/locales/#{vue_plural}/index.js"},
          {:eex, "assets/backend/cypress/integration/spec.js",
           "assets/backend/cypress/integration/#{snake_domain}/#{Recase.to_pascal(vue_singular)}.spec.js"}
        ]

    :ok = Mix.Brando.check_module_name_availability(binding[:module] <> "Controller")
    :ok = Mix.Brando.check_module_name_availability(binding[:module] <> "View")

    Mix.Brando.copy_from(apps(), "priv/templates/brando.gen", "", binding, files)

    instructions = """
    Update your repository by running migrations:

        $ mix ecto.migrate

    Then lint the Vue backend files:

        $ cd assets/backend && yarn lint --fix && cd ../..

    ================================================================================================
    """

    binding = Enum.reduce(@generator_modules, binding, &apply(&1, :after_copy, [&2]))

    # Add content to files
    if sequenced? do
      Mix.Brando.add_to_file(
        "lib/#{Mix.Brando.otp_app()}_web/channels/admin_channel.ex",
        "imports",
        "alias #{binding[:base]}.#{binding[:domain]}",
        singular: true
      )

      Mix.Brando.add_to_file(
        "lib/#{Mix.Brando.otp_app()}_web/channels/admin_channel.ex",
        "macros",
        "sequence #{inspect(plural)}, #{binding[:domain]}.#{binding[:alias]}"
      )

      Mix.Brando.add_to_file(
        "lib/#{Mix.Brando.otp_app()}_web/channels/admin_channel.ex",
        "imports",
        "use Brando.Sequence.Channel",
        singular: true
      )
    end

    Mix.shell().info(instructions)
  end

  def migration_type({k, :image}), do: {k, :jsonb}
  def migration_type({k, :file}), do: {k, :text}
  def migration_type({k, :slug}), do: {k, :slug}
  def migration_type({k, :text}), do: {k, :text}
  def migration_type({k, :status}), do: {k, :integer}
  def migration_type({k, :datetime}), do: {k, :utc_datetime}
  def migration_type({k, type}), do: {k, type}

  defp partition_attrs_and_assocs(attrs) do
    Enum.split_with(attrs, fn
      {_, {:references, _}} -> false
      {_, _} -> true
    end)
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  defp types(attrs) do
    Enum.into(attrs, %{}, fn
      {k, {:references, target}} ->
        {k, {:references, target}}

      {k, {:slug, target}} ->
        {k, {:slug, target}}

      {k, {c, v}} ->
        {k, {c, value_to_type(v)}}

      {k, v} ->
        {k, value_to_type(v)}
    end)
  end

  defp defaults(attrs) do
    Enum.into(attrs, %{}, fn
      {k, :boolean} -> {k, ", default: false"}
      {k, _} -> {k, ""}
    end)
  end

  defp value_to_type(:integer), do: :integer
  defp value_to_type(:text), do: :string
  defp value_to_type(:string), do: :string
  defp value_to_type(:uuid), do: Ecto.UUID
  defp value_to_type(:date), do: :date
  defp value_to_type(:time), do: :time
  defp value_to_type(:datetime), do: :utc_datetime
  defp value_to_type(:status), do: Brando.Type.Status
  defp value_to_type(:image), do: Brando.Type.Image
  defp value_to_type(:file), do: Brando.Type.File
  defp value_to_type(:villain), do: :villain
  defp value_to_type(:gallery), do: :gallery

  defp value_to_type(v) do
    if Code.ensure_loaded?(Ecto.Type) and not Ecto.Type.primitive?(v) do
      Mix.raise("Unknown type `#{v}` given to generator")
    else
      v
    end
  end

  defp apps do
    [".", :brando]
  end
end

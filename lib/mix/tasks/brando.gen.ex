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

    if Mix.env() != :test do
      Mix.Task.run("compile")
    end

    blueprint = Mix.shell().prompt("+ Enter blueprint module") |> String.trim("\n")
    blueprint_module = Module.concat([blueprint])
    build_from_blueprint(blueprint_module)
  end

  defp otp_app, do: Mix.Project.config() |> Keyword.fetch!(:app)

  @spec build_from_blueprint(module) :: no_return
  defp build_from_blueprint(blueprint_module) do
    blueprint = blueprint_module.__blueprint__()
    domain = blueprint.naming.domain

    snake_domain =
      domain
      |> Phoenix.Naming.underscore()
      |> String.split("/")
      |> List.last()

    domain_filename = "lib/#{otp_app()}/#{snake_domain}.ex"
    domain_exists? = File.exists?(domain_filename)

    singular = blueprint.naming.singular |> String.capitalize()
    plural = blueprint.naming.plural

    # build attrs
    attrs = Mix.Brando.attrs(blueprint)
    main_field = attrs |> List.first() |> elem(0)

    sequenced? = blueprint_module.has_trait(Brando.Trait.Sequenced)
    soft_delete? = blueprint_module.has_trait(Brando.Trait.SoftDelete)
    creator? = blueprint_module.has_trait(Brando.Trait.Creator)
    revisioned? = blueprint_module.has_trait(Brando.Trait.Revisioned)
    meta? = blueprint_module.has_trait(Brando.Trait.Meta)
    publish_at? = blueprint_module.has_trait(Brando.Trait.ScheduledPublishing)
    file_field? = blueprint_module.__file_fields__() != []
    image_field? = blueprint_module.__image_fields__() != []
    video_field? = blueprint_module.__video_fields__() != []
    villain? = blueprint_module.__villain_fields__() != []
    gallery? = blueprint_module.__gallery_fields__() != []
    status? = blueprint_module.__status_fields__() != []
    slug? = blueprint_module.__slug_fields__() != []

    binding = Mix.Brando.inflect(singular)
    path = binding[:path]

    img_fields =
      attrs
      |> Enum.map(fn {k, v} -> {v, k} end)
      |> Enum.filter(fn {k, _} -> k == :image end)

    video_fields =
      attrs
      |> Enum.map(fn {k, v} -> {v, k} end)
      |> Enum.filter(fn {k, _} -> k == :video end)

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

    app_module = to_string(Brando.config(:app_module)) |> String.replace("Elixir.", "")
    web_module = to_string(Brando.config(:web_module)) |> String.replace("Elixir.", "")

    module = Enum.join([web_module, binding[:scoped]], ".")

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
          app_module: app_module,
          web_module: web_module,
          attrs: attrs,
          assocs: assocs,
          domain_filename: domain_filename,
          plural: plural,
          route: route,
          file_field: file_field?,
          image_field: image_field?,
          video_field: video_field?,
          villain: villain?,
          gallery: gallery?,
          status: status?,
          slug: slug?,
          sequenced: sequenced?,
          soft_delete: soft_delete?,
          creator: creator?,
          revisioned: revisioned?,
          meta: meta?,
          publish_at: publish_at?,
          img_fields: img_fields,
          video_fields: video_fields,
          file_fields: file_fields,
          villain_fields: villain_fields,
          gallery_fields: gallery_fields,
          module: module,
          params: Mix.Brando.params(attrs),
          snake_domain: snake_domain,
          schema_module: blueprint.modules.schema,
          domain: domain,
          main_field: main_field,
          types: types,
          migration_types: migration_types,
          defaults: defs,
          params: params,
          vue_singular: vue_singular,
          vue_plural: vue_plural
        ]

    binding = Enum.reduce(@generator_modules, binding, &apply(&1, :before_copy, [&2]))

    schema_test_path = "test/schemas/#{path}_test.exs"

    files =
      (domain_exists? && []) ||
        [{:eex, "domain.ex", "lib/application_name/#{snake_domain}.ex"}]

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
          {:eex, "schema_test.exs", schema_test_path},

          # Backend JS
          {:eex, "assets/backend/src/api/graphql/ALL_QUERY.graphql",
           "assets/backend/src/gql/#{snake_domain}/#{singular |> Inflex.underscore() |> Inflex.pluralize() |> String.upcase()}_QUERY.graphql"},
          {:eex, "assets/backend/src/api/graphql/SINGLE_QUERY.graphql",
           "assets/backend/src/gql/#{snake_domain}/#{singular |> Inflex.underscore() |> String.upcase()}_QUERY.graphql"},
          {:eex, "assets/backend/src/api/graphql/FRAGMENT.graphql",
           "assets/backend/src/gql/#{snake_domain}/#{singular |> Inflex.underscore() |> String.upcase()}_FRAGMENT.graphql"},
          {:eex, "assets/backend/src/api/graphql/CREATE_MUTATION.graphql",
           "assets/backend/src/gql/#{snake_domain}/CREATE_#{singular |> Inflex.underscore() |> String.upcase()}_MUTATION.graphql"},
          {:eex, "assets/backend/src/api/graphql/UPDATE_MUTATION.graphql",
           "assets/backend/src/gql/#{snake_domain}/UPDATE_#{singular |> Inflex.underscore() |> String.upcase()}_MUTATION.graphql"},
          {:eex, "assets/backend/src/api/graphql/DELETE_MUTATION.graphql",
           "assets/backend/src/gql/#{snake_domain}/DELETE_#{singular |> Inflex.underscore() |> String.upcase()}_MUTATION.graphql"},
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
           "assets/backend/cypress/integration/#{snake_domain}/#{Recase.to_pascal(vue_singular)}.spec.js"},

          # GQL
          {:eex, "graphql/schema/types/type.ex",
           "lib/application_name/graphql/schema/types/#{path}.ex"},
          {:eex, "graphql/resolvers/resolver.ex",
           "lib/application_name/graphql/resolvers/#{path}_resolver.ex"}
        ]

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
        "alias #{binding[:app_module]}.#{binding[:domain]}",
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
  def migration_type({k, :video}), do: {k, :jsonb}
  def migration_type({k, :file}), do: {k, :jsonb}
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
  defp value_to_type(:slug), do: :string
  defp value_to_type(:uuid), do: Ecto.UUID
  defp value_to_type(:date), do: :date
  defp value_to_type(:time), do: :time
  defp value_to_type(:language), do: :string
  defp value_to_type(:datetime), do: :utc_datetime
  defp value_to_type(:status), do: Brando.Type.Status
  defp value_to_type(:image), do: :image
  defp value_to_type(:video), do: Brando.Type.Video
  defp value_to_type(:file), do: Brando.Type.File
  defp value_to_type(:villain), do: :villain
  defp value_to_type(:gallery), do: :gallery
  defp value_to_type(:enum), do: Ecto.Enum

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

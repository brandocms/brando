defmodule Mix.Tasks.Brando.Gen do
  use Mix.Task

  @shortdoc "Generates a Brando-styled schema"

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
    naming = blueprint_module.__naming__()
    modules = blueprint_module.__modules__()
    domain = naming.domain

    snake_domain =
      domain
      |> Phoenix.Naming.underscore()
      |> String.split("/")
      |> List.last()

    domain_filename = "lib/#{otp_app()}/#{snake_domain}.ex"
    domain_exists? = File.exists?(domain_filename)

    singular = naming.singular |> String.capitalize()
    plural = naming.plural

    # build attrs
    attrs =
      Mix.Brando.attrs(
        Brando.Blueprint.Attributes.__attributes__(blueprint_module),
        Brando.Blueprint.Relations.__relations__(blueprint_module)
      )

    main_field = attrs |> List.first() |> elem(0)

    sequenced? = blueprint_module.has_trait(Brando.Trait.Sequenced)
    soft_delete? = blueprint_module.has_trait(Brando.Trait.SoftDelete)
    translatable? = blueprint_module.has_trait(Brando.Trait.Translatable)
    creator? = blueprint_module.has_trait(Brando.Trait.Creator)
    revisioned? = blueprint_module.has_trait(Brando.Trait.Revisioned)
    meta? = blueprint_module.has_trait(Brando.Trait.Meta)
    publish_at? = blueprint_module.has_trait(Brando.Trait.ScheduledPublishing)
    file_field? = blueprint_module.__file_fields__() != []
    image_field? = blueprint_module.__image_fields__() != []
    video_field? = blueprint_module.__video_fields__() != []
    villain? = blueprint_module.__blocks_fields__() != []
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
    admin_module = to_string(Brando.config(:admin_module)) |> String.replace("Elixir.", "")

    module = Enum.join([web_module, binding[:scoped]], ".")

    # schema
    {attrs, assocs} = partition_attrs_and_assocs(attrs)
    migration_types = Enum.map(attrs, &migration_type/1)
    types = types(attrs)
    defs = defaults(attrs)
    params = Mix.Brando.params(attrs)
    camel_singular = Macro.camelize(singular)
    camel_plural = Macro.camelize(plural)

    binding =
      Keyword.delete(binding, :module) ++
        [
          app_module: app_module,
          web_module: web_module,
          admin_module: admin_module,
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
          translatable: translatable?,
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
          params: params,
          snake_domain: snake_domain,
          schema_module: modules.schema,
          domain: domain,
          main_field: main_field,
          types: types,
          migration_types: migration_types,
          defaults: defs,
          camel_singular: camel_singular,
          camel_plural: camel_plural
        ]

    schema_test_path = "test/schemas/#{path}_test.exs"

    files =
      (domain_exists? && []) ||
        [{:eex, "domain.ex", "lib/application_name/#{snake_domain}.ex"}]

    files =
      files ++
        [
          {:eex, "controller.ex", "lib/application_name_web/controllers/#{path}_controller.ex"},
          {:eex, "detail.html.eex", "lib/application_name_web/controllers/#{binding[:singular]}_html/detail.html.heex"},
          {:eex, "list.html.eex", "lib/application_name_web/controllers/#{binding[:singular]}_html/list.html.heex"},
          {:eex, "html.ex", "lib/application_name_web/controllers/#{binding[:singular]}_html.ex"},

          # ADMIN
          {:eex, "admin/list.ex", "lib/application_name_admin/live/#{snake_domain}/#{binding[:singular]}_list_live.ex"},
          {:eex, "admin/form.ex", "lib/application_name_admin/live/#{snake_domain}/#{binding[:singular]}_form_live.ex"},

          # TEST
          {:eex, "schema_test.exs", schema_test_path}
        ]

    Mix.Brando.copy_from(apps(), "priv/templates/brando.gen", "", binding, files)

    instructions = """
    If you want to manage this schema through the admin, add these routes to your router

        scope "/#{snake_domain}", #{admin_module}.#{domain} do
          live "/#{plural}", #{camel_singular}ListLive
          live "/#{plural}/create", #{camel_singular}FormLive, :create
          live "/#{plural}/update/:entry_id", #{camel_singular}FormLive, :update
        end

    ================================================================================================
    """

    add_to_files(binding)

    Mix.shell().info(instructions)
  end

  def add_to_files(binding) do
    Mix.Brando.add_to_file(
      binding[:domain_filename],
      "types",
      "@type #{binding[:singular]} :: #{binding[:app_module]}.#{binding[:domain]}.#{binding[:scoped]}.t()"
    )

    Mix.Brando.add_to_file(
      binding[:domain_filename],
      "header",
      "alias #{binding[:app_module]}.#{binding[:domain]}.#{binding[:scoped]}"
    )

    domain_code =
      EEx.eval_file(
        Application.app_dir(
          :brando,
          "priv/templates/brando.gen/domain_code.eex"
        ),
        binding
      )

    Mix.Brando.add_to_file(
      binding[:domain_filename],
      "code",
      domain_code
    )

    binding
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
  defp value_to_type(:file), do: :file
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

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
    Mix.shell().info("""
    % Brando HTML generator
    -----------------------

    """)

    domain =
      Mix.shell().prompt("+ Enter domain name (e.g. Blog, Accounts, News)") |> String.trim("\n")

    Mix.shell().info("""
    == Creating domain for #{domain}
    """)

    create_domain(domain)
  end

  defp otp_app do
    Mix.Project.config() |> Keyword.fetch!(:app)
  end

  defp create_domain(domain_name) do
    snake_domain =
      domain_name
      |> Phoenix.Naming.underscore()
      |> String.split("/")
      |> List.last()

    binding = Mix.Brando.inflect(domain_name)

    File.mkdir_p!("lib/#{otp_app()}/#{snake_domain}")
    {domain_code, domain_header, instructions} = create_schema(domain_name)

    File.write!(
      "lib/#{otp_app()}/#{snake_domain}/#{snake_domain}.ex",
      """
      defmodule #{binding[:module]} do
        @moduledoc \"\"\"
        Context for #{binding[:plural]}
        \"\"\"

        alias #{binding[:base]}.Repo

        #{domain_header}\n#{domain_code}
      end
      """
    )

    Mix.shell().info(instructions)
  end

  defp create_schema(domain_name, domain_header \\ "", domain_code \\ "", instructions \\ "") do
    Mix.shell().info("""
    == Schema for #{domain_name}
    """)

    snake_domain =
      domain_name
      |> Phoenix.Naming.underscore()
      |> String.split("/")
      |> List.last()

    singular = Mix.shell().prompt("+ Enter schema name (e.g. Post)") |> String.trim("\n")
    plural = Mix.shell().prompt("+ Enter plural name (e.g. posts)") |> String.trim("\n")

    attrs =
      Mix.shell().prompt("+ Enter schema fields (e.g. name:string avatar:image data:villain)")
      |> String.trim("\n")

    org_attrs = attrs |> String.split(" ")
    attrs = org_attrs |> Mix.Brando.attrs()
    villain? = :villain in Keyword.values(attrs)
    sequenced? = Mix.shell().yes?("\nMake schema sequenceable?")
    image_field? = :image in Keyword.values(attrs)
    binding = Mix.Brando.inflect(singular)
    admin_path = Enum.join(["admin", binding[:path]], "_")
    path = binding[:path]

    route =
      path
      |> String.split("/")
      |> Enum.drop(-1)
      |> Kernel.++([plural])
      |> Enum.join("/")

    module = Enum.join([binding[:base] <> "Web", binding[:scoped]], ".")
    admin_module = Enum.join([binding[:base] <> "Web", "Admin", binding[:scoped]], ".")

    vue_plural = Recase.to_camel(plural)
    vue_singular = Recase.to_camel(singular)

    binding =
      Keyword.delete(binding, :module) ++
        [
          plural: plural,
          route: route,
          image_field: image_field?,
          villain: villain?,
          sequenced: sequenced?,
          module: module,
          admin_module: admin_module,
          admin_path: admin_path,
          gql_inputs: graphql_inputs(attrs),
          gql_types: graphql_types(attrs),
          vue_inputs: vue_inputs(attrs, Recase.to_camel(binding[:singular])),
          vue_defaults: vue_defaults(attrs),
          params: Mix.Brando.params(attrs),
          snake_domain: snake_domain,
          domain: domain_name,
          vue_singular: Recase.to_camel(binding[:singular]),
          vue_plural: Recase.to_camel(vue_plural)
        ]

    args = [singular, plural, org_attrs]

    files = [
      {:eex, "controller.ex", "lib/application_name_web/controllers/#{path}_controller.ex"},
      {:eex, "index.html.eex", "lib/application_name_web/templates/#{path}/index.html.eex"},
      {:eex, "view.ex", "lib/application_name_web/views/#{path}_view.ex"},

      # GQL
      {:eex, "graphql/schema/types/type.ex",
       "lib/application_name/graphql/schema/types/#{path}.ex"},
      {:eex, "graphql/resolvers/resolver.ex",
       "lib/application_name/graphql/resolvers/#{path}_resolver.ex"},

      # Backend JS
      {:eex, "assets/backend/src/store/modules/module.js",
       "assets/backend/src/store/modules/#{vue_plural}.js"},
      {:eex, "assets/backend/src/api/api.js", "assets/backend/src/api/#{vue_singular}.js"},
      {:eex, "assets/backend/src/api/graphql/ALL_QUERY.graphql",
       "assets/backend/src/api/graphql/#{vue_plural}/#{String.upcase(plural)}_QUERY.graphql"},
      {:eex, "assets/backend/src/api/graphql/SINGLE_QUERY.graphql",
       "assets/backend/src/api/graphql/#{vue_plural}/#{String.upcase(singular)}_QUERY.graphql"},
      {:eex, "assets/backend/src/api/graphql/CREATE_MUTATION.graphql",
       "assets/backend/src/api/graphql/#{vue_plural}/CREATE_#{String.upcase(singular)}_MUTATION.graphql"},
      {:eex, "assets/backend/src/api/graphql/UPDATE_MUTATION.graphql",
       "assets/backend/src/api/graphql/#{vue_plural}/UPDATE_#{String.upcase(singular)}_MUTATION.graphql"},
      {:eex, "assets/backend/src/api/graphql/DELETE_MUTATION.graphql",
       "assets/backend/src/api/graphql/#{vue_plural}/DELETE_#{String.upcase(singular)}_MUTATION.graphql"},
      {:eex, "assets/backend/src/menus/menu.js", "assets/backend/src/menus/#{vue_plural}.js"},
      {:eex, "assets/backend/src/routes/route.js", "assets/backend/src/routes/#{vue_plural}.js"},
      {:eex, "assets/backend/src/views/List.vue",
       "assets/backend/src/views/#{snake_domain}/#{Recase.to_pascal(vue_singular)}ListView.vue"},
      {:eex, "assets/backend/src/views/Create.vue",
       "assets/backend/src/views/#{snake_domain}/#{Recase.to_pascal(vue_singular)}CreateView.vue"},
      {:eex, "assets/backend/src/views/Edit.vue",
       "assets/backend/src/views/#{snake_domain}/#{Recase.to_pascal(vue_singular)}EditView.vue"}
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

    instructions =
      instructions <>
        """
        You must add the GraphQL types/mutations/queries to your applications schema
        `lib/#{binding[:application_name]}/graphql/schema.ex`

            query do
              import_brando_queries()

              # local queries
              import_fields :#{binding[:singular]}_queries
            end

            mutation do
              import_brando_mutations()

              # local mutations
              import_fields :#{binding[:singular]}_mutations
            end

        Also add the type imports to your types file
        `lib/#{binding[:application_name]}`/graphql/schema/types.ex`

            # local imports
            import_types #{binding[:base]}.Schema.Types.(TypeHere!)

            #{sequenced_info}

        and then update your repository by running migrations:
            $ mix ecto.migrate

        ================================================================================================
        """

    domain_header =
      domain_header <> "\n  alias #{binding[:base]}.#{binding[:domain]}.#{binding[:scoped]}"

    domain_code = generate_domain_code(domain_code, domain_name, binding, schema_binding)

    if Mix.shell().yes?("\nCreate another schema?") do
      create_schema(domain_name, domain_header, domain_code, instructions)
    else
      {domain_code, domain_header, instructions}
    end
  end

  defp generate_domain_code(domain_code, _, binding, _schema_binding) do
    insert_code = "Repo.insert(changeset)"

    domain_code <>
      """
        @doc \"\"\"
        List all #{binding[:plural]}
        \"\"\"
        def list_#{binding[:plural]} do
          {:ok, Repo.all(#{binding[:alias]})}
        end

        @doc \"\"\"
        Get single #{binding[:singular]}
        \"\"\"
        def get_#{binding[:singular]}(id) do
          case Repo.get(#{binding[:alias]}, id) do
            nil -> {:error, {:#{binding[:singular]}, :not_found}}
            #{binding[:singular]} -> {:ok, #{binding[:singular]}}
          end
        end

        @doc \"\"\"
        Create new #{binding[:singular]}
        \"\"\"
        def create_#{binding[:singular]}(#{binding[:singular]}_params, user \\\\ :system) do
          changeset = #{binding[:alias]}.changeset(%#{binding[:alias]}{}, #{binding[:singular]}_params, user)
          #{insert_code}
        end

        @doc \"\"\"
        Update existing #{binding[:singular]}
        \"\"\"
        def update_#{binding[:singular]}(#{binding[:singular]}_id, #{binding[:singular]}_params, user \\\\ :system) do
          {:ok, #{binding[:singular]}} = get_#{binding[:singular]}(#{binding[:singular]}_id)

          #{binding[:singular]}
          |> #{binding[:alias]}.changeset(#{binding[:singular]}_params, user)
          |> Repo.update()
        end

        @doc \"\"\"
        Delete #{binding[:singular]} by id
        \"\"\"
        def delete_#{binding[:singular]}(id) do
          {:ok, #{binding[:singular]}} = get_#{binding[:singular]}(id)
          Repo.delete(#{binding[:singular]})
          {:ok, #{binding[:singular]}}
        end
      """
  end

  defp graphql_types(attrs) do
    # this is for GraphQL type objects

    Enum.map(attrs, fn
      {k, {:array, _}} ->
        {k, ~s(field #{inspect(k)}, list_of\(:string\))}

      {k, :integer} ->
        {k, ~s(field #{inspect(k)}, :integer)}

      {k, :boolean} ->
        {k, ~s(field #{inspect(k)}, :boolean)}

      {k, :string} ->
        {k, ~s(field #{inspect(k)}, :string)}

      {k, :text} ->
        {k, ~s(field #{inspect(k)}, :string)}

      {k, :date} ->
        {k, ~s(field #{inspect(k)}, :date)}

      {k, :time} ->
        {k, ~s(field #{inspect(k)}, :time)}

      {k, :datetime} ->
        {k, ~s(field #{inspect(k)}, :time)}

      {k, :image} ->
        {k, ~s(field #{inspect(k)}, :image_type)}

      {k, :villain} ->
        fields =
          case k do
            :data ->
              [:data, :html]

            _ ->
              [String.to_atom(to_string(k) <> "_data"), String.to_atom(to_string(k) <> "_html")]
          end

        {k,
         ~s(field #{inspect(Enum.at(fields, 0))}, :json\n    field #{inspect(Enum.at(fields, 1))}, :string)}

      {k, _} ->
        {k, ~s(field #{inspect(k)}, :string)}
    end)
  end

  defp graphql_inputs(attrs) do
    # this is for GraphQL input objects
    Enum.map(attrs, fn
      {k, {:array, _}} ->
        {k, nil, nil}

      {k, :integer} ->
        {k, ~s(field #{inspect(k)}, :integer)}

      {k, :boolean} ->
        {k, ~s(field #{inspect(k)}, :boolean)}

      {k, :string} ->
        {k, ~s(field #{inspect(k)}, :string)}

      {k, :text} ->
        {k, ~s(field #{inspect(k)}, :string)}

      {k, :date} ->
        {k, ~s(field #{inspect(k)}, :date)}

      {k, :time} ->
        {k, ~s(field #{inspect(k)}, :time)}

      {k, :datetime} ->
        {k, ~s(field #{inspect(k)}, :time)}

      {k, :image} ->
        {k, ~s(field #{inspect(k)}, :upload_or_image)}

      {k, :villain} ->
        k = (k == :data && :data) || String.to_atom(Atom.to_string(k) <> "_data")
        {k, ~s(field #{inspect(k)}, :string)}

      {k, _} ->
        {k, ~s(field #{inspect(k)}, :string)}
    end)
  end

  defp vue_defaults(attrs) do
    # this is for vue default objects
    Enum.map(attrs, fn
      {k, {:array, _}} ->
        {k, nil, nil}

      {k, :boolean} ->
        {k, "false"}

      {k, :text} ->
        {k, "''"}

      {k, :string} ->
        {k, "''"}

      {k, :date} ->
        {k, "null"}

      {k, :time} ->
        {k, "null"}

      {k, :datetime} ->
        {k, "null"}

      {k, :image} ->
        {k, "null"}

      {k, :villain} ->
        k = (k == :data && :data) || String.to_atom(Atom.to_string(k) <> "_data")
        {k, "null"}

      {k, _} ->
        {k, "null"}
    end)
  end

  defp vue_inputs(attrs, singular) do
    # this is for vue components
    Enum.map(attrs, fn
      {k, {:array, _}} ->
        {k, nil, nil}

      {k, :boolean} ->
        {k,
         [
           "<KInputCheckbox",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           ":has-error=\"errors.has('#{singular}[#{k}]')\"",
           ":error-text=\"errors.first('#{singular}[#{k}]')\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "data-vv-name=\"#{singular}[#{k}]\"",
           "data-vv-value-path=\"innerValue\"",
           "/>"
         ]}

      {k, :text} ->
        {k,
         [
           "<KInput",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           ":has-error=\"errors.has('#{singular}[#{k}]')\"",
           ":error-text=\"errors.first('#{singular}[#{k}]')\"",
           "v-validate=\"'required'\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "placeholder=\"#{String.capitalize(to_string(k))}\"",
           "data-vv-name=\"#{singular}[#{k}]\"",
           "data-vv-value-path=\"innerValue\"",
           "/>"
         ]}

      {k, :date} ->
        {k,
         [
           "<KInputDatetime",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           ":has-error=\"errors.has('#{singular}[#{k}]')\"",
           ":error-text=\"errors.first('#{singular}[#{k}]')\"",
           "v-validate=\"'required'\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "placeholder=\"#{String.capitalize(to_string(k))}\"",
           "data-vv-name=\"#{singular}[#{k}]\"",
           "data-vv-value-path=\"innerValue\"",
           "/>"
         ]}

      {k, :time} ->
        {k,
         [
           "<KInputDatetime",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           ":has-error=\"errors.has('#{singular}[#{k}]')\"",
           ":error-text=\"errors.first('#{singular}[#{k}]')\"",
           "v-validate=\"'required'\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "placeholder=\"#{String.capitalize(to_string(k))}\"",
           "data-vv-name=\"#{singular}[#{k}]\"",
           "data-vv-value-path=\"innerValue\"",
           "/>"
         ]}

      {k, :datetime} ->
        {k,
         [
           "<KInputDatetime",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           ":has-error=\"errors.has('#{singular}[#{k}]')\"",
           ":error-text=\"errors.first('#{singular}[#{k}]')\"",
           "v-validate=\"'required'\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "placeholder=\"#{String.capitalize(to_string(k))}\"",
           "data-vv-name=\"#{singular}[#{k}]\"",
           "data-vv-value-path=\"innerValue\"",
           "/>"
         ]}

      {k, :image} ->
        {k,
         [
           "<KInputImage",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           ":has-error=\"errors.has('#{singular}[#{k}]')\"",
           ":error-text=\"errors.first('#{singular}[#{k}]')\"",
           "v-validate=\"'required'\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "data-vv-name=\"#{singular}[#{k}]\"",
           "data-vv-value-path=\"innerValue\"",
           "/>"
         ]}

      {k, :villain} ->
        k = (k == :data && :data) || String.to_atom(Atom.to_string(k) <> "_data")

        {k,
         [
           "<Villain",
           ":value=\"#{singular}.#{k}\"",
           "@input=\"#{singular}.#{k} = $event\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "/>"
         ]}

      {k, _} ->
        {k,
         [
           "<KInput",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           ":has-error=\"errors.has('#{singular}[#{k}]')\"",
           ":error-text=\"errors.first('#{singular}[#{k}]')\"",
           "v-validate=\"'required'\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "placeholder=\"#{String.capitalize(to_string(k))}\"",
           "data-vv-name=\"#{singular}[#{k}]\"",
           "data-vv-value-path=\"innerValue\"",
           "/>"
         ]}
    end)
  end

  defp apps do
    [".", :brando]
  end
end

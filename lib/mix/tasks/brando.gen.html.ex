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
        Context for #{binding[:human]}
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
      Mix.shell().prompt("+ Enter schema fields (e.g. name:string avatar:image data:villain image_series:gallery)")
      |> String.trim("\n")

    org_attrs = attrs |> String.split(" ")
    attrs = org_attrs |> Mix.Brando.attrs()
    villain? = :villain in Keyword.values(attrs)
    sequenced? = Mix.shell().yes?("\nMake schema sequenceable?")
    image_field? = :image in Keyword.values(attrs)
    gallery? = :gallery in Keyword.values(attrs)
    binding = Mix.Brando.inflect(singular)
    path = binding[:path]

    route =
      path
      |> String.split("/")
      |> Enum.drop(-1)
      |> Kernel.++([plural])
      |> Enum.join("/")

    module = Enum.join([binding[:base] <> "Web", binding[:scoped]], ".")

    vue_plural = Recase.to_camel(plural)
    vue_singular = Recase.to_camel(singular)

    binding =
      Keyword.delete(binding, :module) ++
        [
          plural: plural,
          route: route,
          image_field: image_field?,
          villain: villain?,
          gallery: gallery?,
          sequenced: sequenced?,
          module: module,
          gql_inputs: graphql_inputs(attrs),
          gql_types: graphql_types(attrs),
          gql_query_fields: graphql_query_fields(attrs),
          list_rows: list_rows(attrs, Recase.to_camel(binding[:singular])),
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
      {:eex_trim, "assets/backend/src/api/graphql/ALL_QUERY.graphql",
       "assets/backend/src/api/graphql/#{vue_plural}/#{String.upcase(plural)}_QUERY.graphql"},
      {:eex_trim, "assets/backend/src/api/graphql/SINGLE_QUERY.graphql",
       "assets/backend/src/api/graphql/#{vue_plural}/#{String.upcase(singular)}_QUERY.graphql"},
      {:eex, "assets/backend/src/api/graphql/CREATE_MUTATION.graphql",
       "assets/backend/src/api/graphql/#{vue_plural}/CREATE_#{String.upcase(singular)}_MUTATION.graphql"},
      {:eex, "assets/backend/src/api/graphql/UPDATE_MUTATION.graphql",
       "assets/backend/src/api/graphql/#{vue_plural}/UPDATE_#{String.upcase(singular)}_MUTATION.graphql"},
      {:eex, "assets/backend/src/api/graphql/DELETE_MUTATION.graphql",
       "assets/backend/src/api/graphql/#{vue_plural}/DELETE_#{String.upcase(singular)}_MUTATION.graphql"},
      {:eex, "assets/backend/src/menus/menu.js", "assets/backend/src/menus/#{vue_plural}.js"},
      {:eex, "assets/backend/src/routes/route.js", "assets/backend/src/routes/#{vue_plural}.js"},
      {:eex_trim, "assets/backend/src/views/List.vue",
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
        Add the sequence helper to your `admin_channel`:

            use Brando.Sequence, :channel
            sequence #{inspect plural}, #{module}

        """
      else
        ""
      end

    gallery_info =
      if gallery? do
        """
        Add this gallery helper to your `admin_channel`:

            def handle_in("#{binding[:singular]}:create_image_series", %{"#{binding[:singular]}_id" => #{binding[:singular]}_id}, socket) do
              user = Guardian.Phoenix.Socket.current_resource(socket)
              {:ok, image_series} = #{domain_name}.create_image_series(#{binding[:singular]}_id, user)
              {:reply, {:ok, %{code: 200, image_series: Map.merge(image_series, %{creator: nil, image_category: nil, images: nil})}}, socket}
            end

        """
      else
        ""
      end

    instructions =
      instructions <>
        """
        You must add the GraphQL types/mutations/queries to your applications schema
        `lib/#{otp_app()}/graphql/schema.ex`

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
        `lib/#{otp_app()}/graphql/schema/types.ex`

            # local imports
            import_types #{binding[:base]}.Schema.Types.#{binding[:alias]}

        #{sequenced_info}
        #{gallery_info}

        and then update your repository by running migrations:
            $ mix ecto.migrate

        ================================================================================================
        """

    domain_header =
      domain_header <> "  alias #{binding[:base]}.#{binding[:domain]}.#{binding[:scoped]}\n"

    domain_code = generate_domain_code(domain_code, domain_name, binding, schema_binding)

    if Mix.shell().yes?("\nCreate another schema?") do
      create_schema(domain_name, domain_header, domain_code, instructions)
    else
      {domain_code, domain_header, instructions}
    end
  end

  defp generate_domain_code(domain_code, _, binding, _schema_binding) do
    insert_code = "Repo.insert(changeset)"

    domain_code = domain_code <>
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
      if binding[:gallery] do
        domain_code <>
        """

        @doc \"\"\"
        Create an image series entry
        \"\"\"
        def create_image_series(#{binding[:singular]}_id, user) do
          {:ok, #{binding[:singular]}} = get_#{binding[:singular]}(#{binding[:singular]}_id)
          {:ok, cat} = Brando.Images.get_or_create_category_id_by_slug("#{binding[:singular]}-gallery", user)

          data = %{
            name: #{binding[:singular]}.name,
            slug: #{binding[:singular]}.slug,
            image_category_id: cat.id
          }

          with {:ok, series} <- Brando.Images.create_series(data, user) do
            cs = Ecto.Changeset.change(#{binding[:singular]}, image_series_id: series.id)
            Repo.update(cs)

            {:ok, series}
          end
        end

      """
      else
        domain_code
      end
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

  defp list_rows(attrs, vue_singular) do
    # this is for List.vue
    Enum.map(attrs, fn
      {k, {:array, _}} ->
        {k, ""}

      {k, :boolean} ->
        {k, ~s(                  <td class="fit">
                    <CheckOrX :val="#{vue_singular}.#{k}" />
                  </td>)}

      {k, :date} ->
        {k, ~s(                  <td class="fit">
                    {{ #{vue_singular}.#{k} | datetime }}
                  </td>)}

      {k, :time} ->
        {k, ~s(                  <td class="fit">
                    {{ #{vue_singular}.#{k} | datetime }}
                  </td>)}

      {k, :datetime} ->
        {k, ~s(                  <td class="fit">
                    {{ #{vue_singular}.#{k} | datetime }}
                  </td>)}

      {k, :image} ->
        {k, ~s(                  <td class="fit">
                    <img
                      v-if="#{vue_singular}.#{k}"
                      :src="#{vue_singular}.#{k}.thumb"
                      class="avatar-sm img-border-lg" />
                  </td>)}

      {k, :villain} ->
        {k, ""}

      {k, :gallery} ->
        {k, ~s(                  <td class="fit">
                    <template v-if="#{vue_singular}.#{k}_id">
                      <ModalImageSeries
                        :selectedImages="selectedImages"
                        :imageSeriesId="#{vue_singular}.#{k}_id"
                        :showModal="showImageSeriesModal === #{vue_singular}.#{k}_id"
                        @close="closeImageSeriesModal"
                        v-if="showImageSeriesModal === #{vue_singular}.#{k}_id"
                      />
                      <button @click.prevent="openImageSeriesModal\(#{vue_singular}.#{k}_id\)" class="btn btn-white" v-b-popover.hover.top="'Rediger galleri'">
                        <i class="fal fa-fw fa-images"> </i>
                      </button>
                    </template>
                    <template v-else>
                      <button @click.prevent="createImageSeries\(#{vue_singular}.id\)" class="btn btn-white" v-b-popover.hover.top="'Lag bildegalleri'">
                        <i class="fal fa-fw fa-plus"> </i>
                      </button>
                    </template>
                  </td>)}

      {k, _} ->
        {k, ~s(                  <td class="fit">
                    {{ #{vue_singular}.#{k} }}
                  </td>)}
    end)
  end


  defp graphql_query_fields(attrs) do
    # this is for GraphQL query fields
    Enum.map(attrs, fn
      {k, {:array, _}} ->
        {k, ~s(#{k})}

      {k, :integer} ->
        {k, ~s(#{k})}

      {k, :boolean} ->
        {k, ~s(#{k})}

      {k, :string} ->
        {k, ~s(#{k})}

      {k, :text} ->
        {k, ~s(#{k})}

      {k, :date} ->
        {k, ~s(#{k})}

      {k, :time} ->
        {k, ~s(#{k})}

      {k, :datetime} ->
        {k, ~s(#{k})}

      {k, :gallery} ->
        {k, ~s(#{k}_id)}

      {k, :image} ->
        image_code = "#{k} {\n      thumb: url(size: \"original\")\n      focal\n    }"
        {k, image_code}

      {k, :villain} ->
        case k do
          :data ->
            {k, ~s(#{k})}

          _ ->
            {k, ~s(#{k}_data)}
        end
      {k, _} ->
        {k, ~s(#{k})}
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

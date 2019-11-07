# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
defmodule Mix.Tasks.Brando.Gen.Html do
  use Mix.Task

  @shortdoc "Generates a Brando-styled schema"

  @moduledoc """
  Generates a Brando resource.

      mix brando.gen.html

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
      Mix.shell().prompt(
        "+ Enter schema fields (e.g. name:string meta_description:text avatar:image data:villain image_series:gallery user:references:users)"
      )
      |> String.trim("\n")

    org_attrs = attrs |> String.split(" ")
    attrs = org_attrs |> Mix.Brando.attrs()
    villain? = :villain in Keyword.values(attrs)
    sequenced? = Mix.shell().yes?("\nMake schema sequenceable?")
    soft_delete? = Mix.shell().yes?("\nAdd soft deletion?")
    image_field? = :image in Keyword.values(attrs)
    gallery? = :gallery in Keyword.values(attrs)
    binding = Mix.Brando.inflect(singular)
    path = binding[:path]

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
      |> Enum.map(fn {k, v} -> {v, "#{k}_id"} end)
      |> Enum.filter(fn {k, _} -> k == :gallery end)

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
          soft_delete: soft_delete?,
          img_fields: img_fields,
          file_fields: file_fields,
          villain_fields: villain_fields,
          gallery_fields: gallery_fields,
          module: module,
          gql_inputs: graphql_inputs(attrs),
          gql_types: graphql_types(attrs),
          gql_query_fields: graphql_query_fields(attrs),
          list_rows: list_rows(attrs, Recase.to_camel(binding[:singular])),
          vue_inputs: vue_inputs(attrs, Recase.to_camel(binding[:singular])),
          cypress_fields: cypress_fields(attrs, Recase.to_camel(binding[:singular])),
          vue_defaults: vue_defaults(attrs),
          params: Mix.Brando.params(attrs),
          snake_domain: snake_domain,
          domain: domain_name,
          vue_singular: Recase.to_camel(binding[:singular]),
          vue_plural: Recase.to_camel(vue_plural)
        ]

    args = [singular, plural, org_attrs]

    files =
      (domain_exists? && []) ||
        [{:eex, "domain.ex", "lib/application_name/#{snake_domain}/#{snake_domain}.ex"}]

    files =
      files ++
        [
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
          {:eex, "assets/backend/src/routes/route.js",
           "assets/backend/src/routes/#{vue_plural}.js"},
          {:eex, "assets/backend/src/views/List.vue",
           "assets/backend/src/views/#{snake_domain}/#{Recase.to_pascal(vue_singular)}ListView.vue"},
          {:eex_trim, "assets/backend/src/views/Create.vue",
           "assets/backend/src/views/#{snake_domain}/#{Recase.to_pascal(vue_singular)}CreateView.vue"},
          {:eex_trim, "assets/backend/src/views/Edit.vue",
           "assets/backend/src/views/#{snake_domain}/#{Recase.to_pascal(vue_singular)}EditView.vue"},
          {:eex_trim, "assets/backend/src/views/Form.vue",
           "assets/backend/src/views/#{snake_domain}/#{Recase.to_pascal(vue_singular)}Form.vue"},
          {:eex, "assets/backend/cypress/integration/spec.js",
           "assets/backend/cypress/integration/#{snake_domain}/#{Recase.to_pascal(vue_singular)}.spec.js"}
        ]

    {files, args} =
      if sequenced? do
        {files, args ++ ["--sequenced"]}
      else
        {files, args}
      end

    {files, args} =
      if soft_delete? do
        {files, args ++ ["--softdelete"]}
      else
        {files, args}
      end

    {files, args} =
      if gallery? do
        {files, args ++ ["--gallery"]}
      else
        {files, args}
      end

    :ok = Mix.Brando.check_module_name_availability(binding[:module] <> "Controller")
    :ok = Mix.Brando.check_module_name_availability(binding[:module] <> "View")

    Mix.Tasks.Brando.Gen.Schema.run(args, domain_name)

    Mix.Brando.copy_from(apps(), "priv/templates/brando.gen.html", "", binding, files)

    instructions = """
    Update your repository by running migrations:
        $ mix ecto.migrate
    ================================================================================================
    """

    # Add content to files

    Mix.Brando.add_to_file(
      domain_filename,
      "types",
      "@type #{binding[:singular]} :: #{binding[:base]}.#{binding[:domain]}.#{binding[:scoped]}.t()"
    )

    Mix.Brando.add_to_file(
      domain_filename,
      "header",
      "alias #{binding[:base]}.#{binding[:domain]}.#{binding[:scoped]}"
    )

    domain_code =
      EEx.eval_file(
        Application.app_dir(
          :brando,
          "priv/templates/brando.gen.html/domain_code.eex"
        ),
        binding
      )

    Mix.Brando.add_to_file(
      domain_filename,
      "code",
      domain_code
    )

    ## MENUS

    Mix.Brando.add_to_file(
      "assets/backend/src/menus/index.js",
      "imports",
      "import #{binding[:plural]} from './#{binding[:plural]}'"
    )

    Mix.Brando.add_to_file(
      "assets/backend/src/menus/index.js",
      "content",
      "store.commit('menu/STORE_MENU', #{binding[:plural]})"
    )

    ## ROUTES

    Mix.Brando.add_to_file(
      "assets/backend/src/routes/index.js",
      "imports",
      "import #{binding[:plural]} from './#{binding[:plural]}'"
    )

    Mix.Brando.add_to_file(
      "assets/backend/src/routes/index.js",
      "content",
      "#{binding[:plural]},"
    )

    ## VUEX STORES

    Mix.Brando.add_to_file(
      "assets/backend/src/store/index.js",
      "imports",
      "import { #{binding[:plural]} } from './modules/#{binding[:plural]}'"
    )

    Mix.Brando.add_to_file(
      "assets/backend/src/store/index.js",
      "content",
      "#{binding[:plural]},"
    )

    ## GQL SCHEMA

    Mix.Brando.add_to_file(
      "lib/#{Mix.Brando.otp_app()}/graphql/schema.ex",
      "dataloader",
      "  |> Dataloader.add_source(#{binding[:base]}.#{binding[:domain]}, #{binding[:base]}.#{
        binding[:domain]
      }.data())",
      :singular
    )

    Mix.Brando.add_to_file(
      "lib/#{Mix.Brando.otp_app()}/graphql/schema.ex",
      "queries",
      "import_fields :#{binding[:singular]}_queries"
    )

    Mix.Brando.add_to_file(
      "lib/#{Mix.Brando.otp_app()}/graphql/schema.ex",
      "mutations",
      "import_fields :#{binding[:singular]}_mutations"
    )

    ## GQL TYPES
    Mix.Brando.add_to_file(
      "lib/#{Mix.Brando.otp_app()}/graphql/schema/types.ex",
      "types",
      "import_types #{binding[:base]}.Schema.Types.#{binding[:alias]}"
    )

    ## ADMIN CHANNEL GALLERY
    if gallery? do
      ins = """
      def handle_in("#{binding[:singular]}:create_image_series", %{"#{binding[:singular]}_id" => #{
        binding[:singular]
      }_id}, socket) do
        user = Guardian.Phoenix.Socket.current_resource(socket)
        {:ok, image_series} = #{domain_name}.create_image_series(#{binding[:singular]}_id, user)
        {:reply, {:ok, %{code: 200, image_series: Map.merge(image_series, %{creator: nil, image_category: nil, images: nil})}}, socket}
      end
      """

      Mix.Brando.add_to_file(
        "lib/#{Mix.Brando.otp_app()}_web/channels/admin_channel.ex",
        "imports",
        "alias #{binding[:base]}.#{binding[:domain]}",
        :singular
      )

      Mix.Brando.add_to_file(
        "lib/#{Mix.Brando.otp_app()}_web/channels/admin_channel.ex",
        "functions",
        ins
      )
    end

    if sequenced? do
      Mix.Brando.add_to_file(
        "lib/#{Mix.Brando.otp_app()}_web/channels/admin_channel.ex",
        "imports",
        "alias #{binding[:base]}.#{binding[:domain]}",
        :singular
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
        :singular
      )
    end

    ## Cypress / factory stuff
    Mix.Brando.add_to_file(
      "lib/#{Mix.Brando.otp_app()}/factory.ex",
      "aliases",
      "alias #{binding[:base]}.#{binding[:domain]}.#{binding[:alias]}"
    )

    factory_code =
      EEx.eval_file(
        Application.app_dir(
          :brando,
          "priv/templates/brando.gen.html/factory_function.eex"
        ),
        binding
      )

    Mix.Brando.add_to_file(
      "lib/#{Mix.Brando.otp_app()}/factory.ex",
      "functions",
      factory_code
    )

    Mix.shell().info(instructions)
  end

  ##
  defp graphql_types(attrs) do
    # this is for GraphQL type objects

    Enum.map(attrs, fn
      {k, {:array, _}} ->
        {k, ~s<field #{inspect(k)}, list_of\(:string\)>}

      {k, :integer} ->
        {k, ~s<field #{inspect(k)}, :integer>}

      {k, :boolean} ->
        {k, ~s<field #{inspect(k)}, :boolean>}

      {k, :string} ->
        {k, ~s<field #{inspect(k)}, :string>}

      {k, :text} ->
        {k, ~s<field #{inspect(k)}, :string>}

      {k, :date} ->
        {k, ~s<field #{inspect(k)}, :date>}

      {k, :time} ->
        {k, ~s<field #{inspect(k)}, :time>}

      {k, :datetime} ->
        {k, ~s<field #{inspect(k)}, :time>}

      {k, :file} ->
        {k, ~s<field #{inspect(k)}, :file_type>}

      {k, :image} ->
        {k, ~s<field #{inspect(k)}, :image_type>}

      {k, :villain} ->
        fields =
          case k do
            :data ->
              [:data, :html]

            _ ->
              [String.to_atom(to_string(k) <> "_data"), String.to_atom(to_string(k) <> "_html")]
          end

        {k,
         ~s<field #{inspect(Enum.at(fields, 0))}, :json\n    field #{inspect(Enum.at(fields, 1))}, :string>}

      {k, :gallery} ->
        {k, ~s<field #{inspect(k)}_id, :id>}

      {k, _} ->
        {k, ~s<field #{inspect(k)}, :string>}
    end)
  end

  defp list_rows(attrs, vue_singular) do
    # this is for List.vue
    Enum.map(attrs, fn
      {k, {:array, _}} ->
        {k, ""}

      {k, :boolean} ->
        {k, ~s(<td class="fit">
                    <CheckOrX :val="#{vue_singular}.#{k}" />
                  </td>)}

      {k, :date} ->
        {k, ~s(<td class="fit">
                    {{ #{vue_singular}.#{k} | datetime }}
                  </td>)}

      {k, :time} ->
        {k, ~s(<td class="fit">
                    {{ #{vue_singular}.#{k} | datetime }}
                  </td>)}

      {k, :datetime} ->
        {k, ~s(<td class="fit">
                    {{ #{vue_singular}.#{k} | datetime }}
                  </td>)}

      {k, :image} ->
        {k, ~s(<td class="fit">
                    <img
                      v-if="#{vue_singular}.#{k}"
                      :src="#{vue_singular}.#{k}.thumb"
                      class="avatar-sm img-border-lg" />
                  </td>)}

      {k, :villain} ->
        {k, ""}

      {k, :gallery} ->
        {k, ~s(<td class="fit">
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
        {k, ~s(<td class="fit">
                    {{ #{vue_singular}.#{k} }}
                  </td>)}
    end)
  end

  defp graphql_query_fields(attrs) do
    # this is for GraphQL query fields
    Enum.map(attrs, fn
      {k, {:array, _}} ->
        {k, k}

      {k, :integer} ->
        {k, k}

      {k, :boolean} ->
        {k, k}

      {k, :string} ->
        {k, k}

      {k, :text} ->
        {k, k}

      {k, :date} ->
        {k, k}

      {k, :time} ->
        {k, k}

      {k, :datetime} ->
        {k, k}

      {k, :gallery} ->
        {k, ~s<#{k}_id>}

      {k, :file} ->
        file_code = "#{k} {\n      url\n    }"
        {k, file_code}

      {k, :image} ->
        image_code = "#{k} {\n      thumb: url(size: \"original\")\n      focal\n    }"
        {k, image_code}

      {k, :villain} ->
        case k do
          :data ->
            {k, k}

          _ ->
            {k, ~s<#{k}_data>}
        end

      {k, _} ->
        {k, k}
    end)
  end

  defp graphql_inputs(attrs) do
    # this is for GraphQL input objects
    Enum.map(attrs, fn
      {k, {:array, _}} ->
        {k, nil, nil}

      {k, :integer} ->
        {k, ~s<field #{inspect(k)}, :integer>}

      {k, :boolean} ->
        {k, ~s<field #{inspect(k)}, :boolean>}

      {k, :string} ->
        {k, ~s<field #{inspect(k)}, :string>}

      {k, :text} ->
        {k, ~s<field #{inspect(k)}, :string>}

      {k, :date} ->
        {k, ~s<field #{inspect(k)}, :date>}

      {k, :time} ->
        {k, ~s<field #{inspect(k)}, :time>}

      {k, :datetime} ->
        {k, ~s<field #{inspect(k)}, :time>}

      {k, :image} ->
        {k, ~s<field #{inspect(k)}, :upload_or_image>}

      {k, :file} ->
        {k, ~s<field #{inspect(k)}, :upload>}

      {k, :villain} ->
        k = (k == :data && :data) || String.to_atom(Atom.to_string(k) <> "_data")
        {k, ~s<field #{inspect(k)}, :json>}

      {k, :gallery} ->
        {k, ~s<field #{inspect(k)}_id, :id>}

      {k, _} ->
        {k, ~s<field #{inspect(k)}, :string>}
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
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "/>"
         ]}

      {k, :text} ->
        {k,
         [
           "<KInput",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           "rules=\"required\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "placeholder=\"#{String.capitalize(to_string(k))}\"",
           "/>"
         ]}

      {k, :date} ->
        {k,
         [
           "<KInputDatetime",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           "rules=\"required\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "placeholder=\"#{String.capitalize(to_string(k))}\"",
           "/>"
         ]}

      {k, :time} ->
        {k,
         [
           "<KInputDatetime",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           "rules=\"required\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "placeholder=\"#{String.capitalize(to_string(k))}\"",
           "/>"
         ]}

      {k, :datetime} ->
        {k,
         [
           "<KInputDatetime",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           "rules=\"required\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "placeholder=\"#{String.capitalize(to_string(k))}\"",
           "/>"
         ]}

      {k, :image} ->
        {k,
         [
           "<KInputImage",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           "rules=\"required\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "/>"
         ]}

      {k, :file} ->
        {k,
         [
           "<KInputFile",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           "rules=\"required\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "/>"
         ]}

      {k, :villain} ->
        k = (k == :data && :data) || String.to_atom(Atom.to_string(k) <> "_data")

        {k,
         [
           "<Villain",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           "rules=\"required\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\""
         ]}

      {k, _} ->
        {k,
         [
           "<KInput",
           "v-model=\"#{singular}.#{k}\"",
           ":value=\"#{singular}.#{k}\"",
           "rules=\"required\"",
           "name=\"#{singular}[#{k}]\"",
           "label=\"#{String.capitalize(to_string(k))}\"",
           "placeholder=\"#{String.capitalize(to_string(k))}\"",
           "/>"
         ]}
    end)
  end

  defp cypress_fields(attrs, singular) do
    # this is for vue components
    Enum.map(attrs, fn
      {k, :boolean} ->
        {k, ["cy.get('##{singular}_#{k}_').clear().check()"]}

      {k, :text} ->
        {k, ["cy.get('##{singular}_#{k}_').clear().type('Default Text Value')"]}

      {k, :date} ->
        {k,
         [
           "cy.get('##{singular}_#{k}_').siblings('.form-control').click()",
           "cy.get('.today').click()"
         ]}

      {k, :time} ->
        {k,
         [
           "cy.get('##{singular}_#{k}_').siblings('.form-control').click()",
           "cy.get('.today').click()"
         ]}

      {k, :datetime} ->
        {k,
         [
           "cy.get('##{singular}_#{k}_').siblings('.form-control').click()",
           "cy.get('.today').click()"
         ]}

      {k, :image} ->
        {k,
         [
           "cy.fixture('jpeg.jpg', 'base64').then(fileContent => {",
           "  cy.get('##{singular}_#{k}_').upload({ fileContent, fileName: 'jpeg.jpg', mimeType: 'image/jpeg' })",
           "})"
         ]}

      {k, :file} ->
        {k,
         [
           "cy.fixture('example.json', 'base64').then(fileContent => {",
           "  cy.get('##{singular}_#{k}_').upload({ fileContent, fileName: 'example.json', mimeType: 'application/json' })",
           "})"
         ]}

      {k, :villain} ->
        {k,
         [
           "cy.get('.villain-editor-plus-inactive > a').click()",
           "cy.get('.villain-editor-plus-available-blocks > :nth-child(1)').click()",
           "cy.get('.ql-editor > p').click().type('This is a paragraph')"
         ]}

      {k, _} ->
        {k, ["cy.get('##{singular}_#{k}_').clear().type('Default value')"]}
    end)
  end

  defp apps do
    [".", :brando]
  end
end

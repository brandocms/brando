defmodule Brando.Blueprint do
  @moduledoc """

  # Override Gettext module

  If you have a nonstandard named gettext module for your app (not MyAppAdmin.Gettext),
  you can supply a `gettext_module` option to your use statement:

      use Brando.Blueprint,
        application: "MyApp",
        # ...
        gettext_module: MyApp.Gettext.Frontend


  # Assets

      assets do
        asset :cover, :image, cfg: [...]
      end

  # Relations

  ## Many to many

    - create the join schema yourself

      use Brando.Blueprint,
        application: "MyApp",
        domain: "Projects",
        schema: "ProjectWorker",
        singular: "project_worker",
        plural: "project_workers"

      relations do
        relation :project, :belongs_to, module: Project
        relation :worker, :belongs_to, module: Worker
      end

    - then add the relation as a m2m:

      use Brando.Blueprint,
        application: "MyApp",
        domain: "Projects",
        schema: "Project",
        singular: "project",
        plural: "projects"

      relations do
        relation :workers, :many_to_many, module: Worker, join_through: ProjectWorker, cast: true
      end

    # add `cast: :true` to :projects_workers opts if you need M2M casting


  ## Embedded schema

      use Brando.Blueprint,
        application: "MyApp",
        domain: "Projects",
        schema: "Project",
        singular: "project",
        plural: "projects"

      data_layer :embedded

  ## UUID primary key

      use Brando.Blueprint,
        application: "MyApp",
        domain: "Projects",
        schema: "Project",
        singular: "project",
        plural: "projects"

      primary_key :uuid

      # for relations that have uuids
      relations do
        relation :some_module, :belongs_to, module: SomeModule, type: :binary_id
      end

  # Extra changesets

  Sometimes you will need additional changeset functions to process different
  subsets of your fields. Currently you'd just add your own function to your schema:

  ```elixir
  def name_changeset(schema, params, user \\ :system) do
    schema
    |> cast(params, [:name])
    |> validate_required([:name])
  end
  ```

  Then force your mutation to use this changeset by passing it explicitly:

  ```elixir
  {:ok, project} = Projects.update_project(
    project_id,
    %{"name" => "New Name"},
    user, changeset: &Projects.Project.name_changeset/3)
  )
  ```

  """
  alias Brando.Exception.BlueprintError
  alias Ecto.Changeset

  alias Brando.Blueprint.Constraints
  alias Brando.Blueprint.Asset
  alias Brando.Blueprint.Assets
  alias Brando.Blueprint.Relations
  alias Brando.Blueprint.Unique
  alias Brando.Blueprint.Upload
  alias Brando.Blueprint.Villain
  alias Brando.Trait

  defstruct naming: %{},
            modules: %{},
            translations: [],
            attributes: [],
            relations: [],
            assets: [],
            listings: [],
            form: %{},
            traits: []

  defmacro __using__(opts) do
    Module.register_attribute(__CALLER__.module, :application, accumulate: false)
    Module.put_attribute(__CALLER__.module, :application, Keyword.fetch!(opts, :application))
    Module.register_attribute(__CALLER__.module, :domain, accumulate: false)
    Module.put_attribute(__CALLER__.module, :domain, Keyword.fetch!(opts, :domain))
    Module.register_attribute(__CALLER__.module, :schema, accumulate: false)
    Module.put_attribute(__CALLER__.module, :schema, Keyword.fetch!(opts, :schema))
    Module.register_attribute(__CALLER__.module, :singular, accumulate: false)
    Module.put_attribute(__CALLER__.module, :singular, Keyword.fetch!(opts, :singular))
    Module.register_attribute(__CALLER__.module, :plural, accumulate: false)
    Module.put_attribute(__CALLER__.module, :plural, Keyword.fetch!(opts, :plural))
    Module.register_attribute(__CALLER__.module, :gettext_module, accumulate: false)
    Module.register_attribute(__CALLER__.module, :brando_macro_context, accumulate: false)
    Module.put_attribute(__CALLER__.module, :brando_macro_context, nil)

    Module.put_attribute(
      __CALLER__.module,
      :gettext_module,
      Macro.expand(Keyword.get(opts, :gettext_module), __CALLER__)
    )

    Module.register_attribute(__CALLER__.module, :ctx, accumulate: false)
    Module.register_attribute(__CALLER__.module, :json_ld_fields, accumulate: true)
    Module.register_attribute(__CALLER__.module, :json_ld_schema, accumulate: false)
    Module.register_attribute(__CALLER__.module, :meta_fields, accumulate: true)
    Module.register_attribute(__CALLER__.module, :traits, accumulate: true)
    Module.register_attribute(__CALLER__.module, :attrs, accumulate: true)
    Module.register_attribute(__CALLER__.module, :relations, accumulate: true)
    Module.register_attribute(__CALLER__.module, :assets, accumulate: true)
    Module.register_attribute(__CALLER__.module, :forms, accumulate: true)
    Module.register_attribute(__CALLER__.module, :listings, accumulate: true)
    Module.register_attribute(__CALLER__.module, :translations, accumulate: false)
    Module.register_attribute(__CALLER__.module, :table_name, accumulate: false)
    Module.register_attribute(__CALLER__.module, :data_layer, accumulate: false)
    Module.register_attribute(__CALLER__.module, :primary_key, accumulate: false)
    Module.register_attribute(__CALLER__.module, :allow_mark_as_deleted, accumulate: false)
    Module.register_attribute(__CALLER__.module, :factory, accumulate: false)

    quote location: :keep do
      @data_layer :database
      @allow_mark_as_deleted false
      @primary_key {:id, :id, autogenerate: true}
      @translations %{}
      @factory %{}

      if String.downcase(@domain) == String.downcase(@plural) do
        @table_name "#{@plural}"
      else
        @table_name "#{String.downcase(@domain)}_#{@plural}"
      end

      @before_compile Brando.Blueprint
      @after_compile Brando.Blueprint

      use Ecto.Schema
      import Ecto.Changeset

      import unquote(__MODULE__)
      import unquote(__MODULE__).AbsoluteURL
      import unquote(__MODULE__).Assets
      import unquote(__MODULE__).Attributes
      import unquote(__MODULE__).Forms
      import unquote(__MODULE__).Identifier
      import unquote(__MODULE__).JSONLD
      import unquote(__MODULE__).Listings
      import unquote(__MODULE__).Listings.Components
      import unquote(__MODULE__).Meta
      import unquote(__MODULE__).Naming
      import unquote(__MODULE__).Relations
      import unquote(__MODULE__).Trait
      import unquote(__MODULE__).Translations
      import unquote(__MODULE__).Utils

      import Brando.Utils.Schema
      import Phoenix.Component, except: [form: 1]

      def __absolute_url__(_), do: nil
      defoverridable __absolute_url__: 1

      def __has_absolute_url__, do: false
      defoverridable __has_absolute_url__: 0

      def __has_identifier__, do: false
      defoverridable __has_identifier__: 0

      def __persist_identifier__, do: true
      defoverridable __persist_identifier__: 0
    end
  end

  defmacro maybe_build_related_identifiers_modules(module, _name, relations) do
    # check if we have any :entries fields
    quote do
      entries_rels = Enum.filter(unquote(relations), &(&1.type == :entries))

      if entries_rels != [] do
        for entries_rel <- entries_rels do
          parent_table_name = @table_name
          parent_module = Module.concat([@application, @domain, @schema])

          defmodule Module.concat([
                      unquote(module),
                      "#{Phoenix.Naming.camelize(to_string(entries_rel.name))}Identifier"
                    ]) do
            use Ecto.Schema
            import Ecto.Query

            schema "#{parent_table_name}_#{entries_rel.name}_identifiers" do
              Ecto.Schema.belongs_to(
                :parent,
                parent_module
              )

              Ecto.Schema.belongs_to(
                :identifier,
                Brando.Content.Identifier
              )

              Ecto.Schema.field(:sequence, :integer)
              Ecto.Schema.timestamps()
            end

            def changeset(struct, attrs, _user, sequence, _opts) do
              struct
              |> cast(attrs, [:parent_id, :identifier_id])
              |> change(sequence: sequence)
            end
          end
        end
      end
    end
  end

  defmacro maybe_build_blocks_modules(module, _name, relations) do
    # check if we have any :blocks fields
    quote do
      blocks_rels =
        Enum.filter(unquote(relations), &(&1.type == :has_many && &1.opts.module == :blocks))

      if blocks_rels != [] do
        for blocks_rel <- blocks_rels do
          parent_module = Module.concat([@application, @domain, @schema])
          parent_table_name = @table_name

          defmodule Module.concat([
                      unquote(module),
                      "#{Phoenix.Naming.camelize(to_string(blocks_rel.name))}"
                    ]) do
            use Ecto.Schema
            import Ecto.Query

            schema "#{parent_table_name}_#{blocks_rel.name}" do
              Ecto.Schema.belongs_to(:entry, parent_module)
              Ecto.Schema.belongs_to(:block, Brando.Content.Block, on_replace: :update)
              Ecto.Schema.field(:sequence, :integer)
              Ecto.Schema.field(:marked_as_deleted, :boolean, default: false, virtual: true)
            end

            @parent_table_name parent_table_name
            def changeset(entry_block, attrs, user, recursive? \\ false) do
              entry_block
              |> cast(attrs, [:entry_id, :block_id, :sequence])
              |> Brando.Content.Block.maybe_cast_recursive(recursive?, user)
              |> unique_constraint([:entry, :block],
                name: "#{@parent_table_name}_blocks_entry_id_block_id_index"
              )
            end
          end
        end
      end
    end
  end

  defmacro build_attrs(attrs) do
    quote do
      Enum.map(unquote(attrs), fn
        %{name: :inserted_at} ->
          Ecto.Schema.timestamps()

        %{name: :updated_at} ->
          []

        attr ->
          Ecto.Schema.field(
            attr.name,
            to_ecto_type(attr.type),
            to_ecto_opts(attr.type, attr.opts)
          )
      end)
    end
  end

  defmacro build_relations(module, relations) do
    quote do
      Enum.map(unquote(relations), fn
        %{type: :belongs_to, name: name, opts: opts} ->
          referenced_module = Map.fetch!(opts, :module)

          Ecto.Schema.belongs_to(
            name,
            referenced_module,
            to_ecto_opts(:belongs_to, opts)
          )

        %{type: :has_one, name: name, opts: opts} ->
          referenced_module = Map.fetch!(opts, :module)

          Ecto.Schema.has_one(
            name,
            referenced_module,
            to_ecto_opts(:has_one, opts)
          )

        %{type: :many_to_many, name: name, opts: opts} ->
          Ecto.Schema.many_to_many(
            name,
            Map.fetch!(opts, :module),
            to_ecto_opts(:many_to_many, opts)
          )

        %{type: :has_many, name: name, opts: %{through: through} = opts} ->
          Ecto.Schema.has_many(
            name,
            to_ecto_opts(:has_many, opts)
          )

        %{type: :has_many, name: rel_name, opts: %{module: :blocks}} ->
          main_module = unquote(module)
          rel_module = rel_name |> to_string() |> Macro.camelize() |> String.to_atom()
          block_module = Module.concat([main_module, rel_module])

          [
            Ecto.Schema.field(:"rendered_#{rel_name}", :string),
            Ecto.Schema.field(:"rendered_#{rel_name}_at", :utc_datetime),
            Ecto.Schema.has_many(
              :"entry_#{rel_name}",
              block_module,
              preload_order: [asc: :sequence],
              on_replace: :delete,
              foreign_key: :entry_id
            ),
            Ecto.Schema.has_many(
              rel_name,
              through: [:"entry_#{rel_name}", :block],
              preload_order: [asc: :sequence]
            )
          ]

        %{type: :has_many, name: :alternates, opts: %{module: :alternates}} ->
          main_module = unquote(module)
          alternate_module = Module.concat([main_module, Alternate])

          [
            Ecto.Schema.has_many(
              :alternates,
              alternate_module,
              on_replace: :delete,
              foreign_key: :linked_entry_id
            ),
            Ecto.Schema.has_many(
              :alternate_entries,
              through: [:alternates, :entry]
            )
          ]

        %{type: :has_many, name: name, opts: opts} ->
          Ecto.Schema.has_many(
            name,
            Map.fetch!(opts, :module),
            to_ecto_opts(:has_many, opts)
          )

        %{type: :embeds_one, name: name, opts: opts} ->
          Ecto.Schema.embeds_one(
            name,
            Map.fetch!(opts, :module),
            to_ecto_opts(:embeds_one, opts)
          )

        %{type: :embeds_many, name: name, opts: opts} ->
          Ecto.Schema.embeds_many(
            name,
            Map.fetch!(opts, :module),
            to_ecto_opts(:embeds_many, opts)
          )

        %{type: :entries, name: name, opts: opts} ->
          entries_module = opts.module

          [
            Ecto.Schema.has_many(
              name,
              entries_module,
              foreign_key: :parent_id,
              preload_order: [asc: :sequence],
              on_replace: :delete
            )
          ]

        relation ->
          require Logger
          Logger.error("==> relation type not caught")
          Logger.error(inspect(relation, pretty: true))
      end)
    end
  end

  defmacro build_assets(assets) do
    quote do
      Enum.map(unquote(assets), fn
        %Asset{type: :file, name: name} ->
          Ecto.Schema.belongs_to(
            name,
            Brando.Files.File,
            on_replace: :update
          )

        %Asset{type: :video, name: name} ->
          Ecto.Schema.belongs_to(
            name,
            Brando.Videos.Video,
            on_replace: :update
          )

        %Asset{type: :image, name: name} ->
          Ecto.Schema.belongs_to(
            name,
            Brando.Images.Image,
            on_replace: :update
          )

        %Asset{type: :gallery, name: name} ->
          Ecto.Schema.belongs_to(
            name,
            Brando.Images.Gallery,
            on_replace: :delete
          )

        asset ->
          require Logger
          Logger.error("==> asset type not caught, #{inspect(asset, pretty: true)}")
      end)
    end
  end

  defmacro build_schema(module, name, attrs, relations, assets) do
    quote location: :keep do
      maybe_build_related_identifiers_modules(unquote(module), unquote(name), unquote(relations))

      schema unquote(name) do
        build_attrs(unquote(attrs))
        build_assets(unquote(assets))
        build_relations(unquote(module), unquote(relations))
      end

      maybe_build_blocks_modules(unquote(module), unquote(name), unquote(relations))
    end
  end

  defmacro build_embedded_schema(module, _name, attrs, relations, assets) do
    quote location: :keep do
      embedded_schema do
        build_attrs(unquote(attrs))
        build_assets(unquote(assets))
        build_relations(unquote(module), unquote(relations))
      end
    end
  end

  def get_required_attrs(attrs) do
    attrs
    |> Enum.filter(&Map.get(&1.opts, :required))
    |> Enum.map(& &1.name)
  end

  def get_optional_attrs(attrs) do
    attrs
    |> Enum.reject(&Map.get(&1.opts, :required))
    |> Villain.maybe_add_villain_html_fields()
    |> Enum.map(& &1.name)
    |> Enum.uniq()
  end

  def get_required_relations(rels) do
    rels
    |> Enum.filter(&Map.get(&1.opts, :required))
    |> Enum.filter(&(&1.type == :belongs_to))
    |> Enum.map(&get_relation_key/1)
  end

  def get_required_assets(assets) do
    assets
    |> Enum.filter(&Map.get(&1.opts, :required))
    |> Enum.filter(&(&1.type != :gallery))
    |> Enum.map(&get_relation_key/1)
  end

  def get_castable_relation_fields(rels) do
    rels
    |> Enum.filter(&(&1.type == :belongs_to))
    |> Enum.map(&(&1.name |> to_string |> Kernel.<>("_id") |> String.to_atom()))
  end

  def get_castable_asset_fields(rels) do
    rels
    |> Enum.filter(&(&1.type in [:file, :image, :video, :gallery]))
    |> Enum.map(&(&1.name |> to_string |> Kernel.<>("_id") |> String.to_atom()))
  end

  def get_relation_key(%{type: :belongs_to, name: name}), do: :"#{name}_id"
  def get_relation_key(%{type: :file, name: name}), do: :"#{name}_id"
  def get_relation_key(%{type: :image, name: name}), do: :"#{name}_id"
  def get_relation_key(%{type: :video, name: name}), do: :"#{name}_id"
  def get_relation_key(%{type: :many_to_many, name: name}), do: name

  def run_translations(module, translations, ctx \\ nil) do
    gettext_module = module.__modules__(:gettext)
    %{domain: domain, schema: schema} = module.__naming__()
    gettext_domain = String.downcase("#{domain}_#{schema}_#{ctx}")

    translations
    |> Enum.map(fn
      {key, value} when is_map(value) ->
        {key, run_translations(module, value, ctx || key)}

      {key, value} ->
        {key, Gettext.dgettext(gettext_module, gettext_domain, value)}
    end)
  end

  def build_id(application, domain, schema) do
    [application, domain, schema]
    |> Enum.map(&String.downcase/1)
    |> Enum.join("-")
  end

  defmacro table(table_name) do
    quote do
      @table_name unquote(table_name)
    end
  end

  defmacro data_layer(type) do
    quote do
      @data_layer unquote(type)
      @allow_mark_as_deleted unquote(type) == :embedded
    end
  end

  defmacro factory(map) do
    quote do
      @factory unquote(map)
    end
  end

  defmacro primary_key(:uuid) do
    quote do
      @primary_key {:id, :binary_id, autogenerate: true}
    end
  end

  defmacro primary_key(:id) do
    quote do
      @primary_key {:id, :id, autogenerate: true}
    end
  end

  defmacro primary_key(opts) do
    quote do
      @primary_key unquote(opts)
    end
  end

  def extract_absolute_url_preloads(env) do
    absolute_url_type = Module.get_attribute(env.module, :absolute_url_type)
    absolute_url_tpl = Module.get_attribute(env.module, :absolute_url_tpl)

    attrs = Module.get_attribute(env.module, :attrs)
    assets = Module.get_attribute(env.module, :assets)
    relations = Module.get_attribute(env.module, :relations)
    traits = Module.get_attribute(env.module, :traits)

    aux_relations = Brando.Trait.get_relations(attrs, assets, relations, traits)
    all_relations = relations ++ aux_relations

    try_relation = fn name ->
      all_relations
      |> Enum.find(fn rel ->
        atom_name = (is_atom(name) && name) || String.to_existing_atom(name)
        rel.name == atom_name
      end)
      |> case do
        nil -> nil
        rel -> rel.name
      end
    end

    case absolute_url_type do
      :liquid ->
        ~r/.*?(entry[.a-zA-Z0-9_]+).*?/
        |> Regex.scan(absolute_url_tpl || "", capture: :all_but_first)
        |> Enum.map(&String.split(List.first(&1), "."))
        |> Enum.filter(&(Enum.count(&1) > 1))
        |> Enum.map(fn
          [_, rel, _] -> try_relation.(rel)
          [_, rel] -> try_relation.(rel)
        end)
        |> Enum.reject(&is_nil(&1))
        |> Enum.uniq()

      :i18n ->
        absolute_url_tpl
        |> Enum.filter(&(Enum.count(&1) > 1))
        |> Enum.map(fn
          [rel, _] -> try_relation.(rel)
          [rel] -> try_relation.(rel)
        end)
        |> Enum.reject(&is_nil(&1))
        |> Enum.uniq()

      nil ->
        []
    end
  end

  defmacro __before_compile__(env) do
    absolute_url_preloads = extract_absolute_url_preloads(env)

    imported_form_modules =
      Module.get_attribute(env.module, :__brando_imported_form_modules__) || []

    imported_listing_modules =
      Module.get_attribute(env.module, :__brando_imported_listing_modules__) || []

    imported_forms =
      for imported_form_module <- imported_form_modules do
        Code.ensure_compiled!(imported_form_module)

        :attributes
        |> imported_form_module.__info__()
        |> Keyword.get_values(:forms)
        |> Macro.escape()
      end

    imported_listings =
      for imported_listing_module <- imported_listing_modules do
        Code.ensure_compiled!(imported_listing_module)

        :attributes
        |> imported_listing_module.__info__()
        |> Keyword.get_values(:listings)
        |> Macro.escape()
      end

    quote location: :keep,
          bind_quoted: [
            imported_forms: imported_forms,
            imported_listings: imported_listings,
            absolute_url_preloads: absolute_url_preloads
          ],
          unquote: false do
      @imported_forms List.flatten(imported_forms)
      @imported_listings List.flatten(imported_listings)
      @absolute_url_preloads absolute_url_preloads

      def __absolute_url_preloads__ do
        @absolute_url_preloads
      end

      def __primary_key__ do
        @primary_key
      end

      def __admin_url__(entry) do
        modules = __modules__()

        case Code.ensure_loaded(modules.admin_form_view) do
          {:module, _} ->
            Brando.routes().admin_live_path(
              Brando.endpoint(),
              modules.admin_form_view,
              :update,
              entry.id
            )

          _ ->
            ""
        end
      end

      @all_attributes Enum.reverse(@attrs) ++
                        Brando.Trait.get_attributes(@attrs, @assets, @relations, @traits) ++
                        Brando.Blueprint.Attributes.maybe_add_marked_as_deleted_attribute(
                          @allow_mark_as_deleted
                        )
      def __attributes__ do
        @all_attributes
      end

      for attr <- @all_attributes do
        def __attribute__(unquote(attr.name)) do
          unquote(Macro.escape(attr))
        end
      end

      def __attribute__(_), do: nil

      unless Enum.empty?(@all_attributes) do
        def __attribute_opts__(name) do
          Map.get(__attribute__(name), :opts, [])
        end
      end

      @all_relations Enum.reverse(@relations) ++
                       Brando.Trait.get_relations(@attrs, @assets, @relations, @traits)
      def __relations__ do
        @all_relations
      end

      for rel <- @all_relations do
        def __relation__(unquote(rel.name)) do
          unquote(Macro.escape(rel))
        end
      end

      def __relation__(unknown_relation) do
        raise BlueprintError,
          message: """
          Unknown relation: #{inspect(unknown_relation)} in schema #{inspect(__MODULE__)}

          Check that you are not referencing a relation that does not exists,
          usually this is due to a typo when declaring your forms.

          """
      end

      unless Enum.empty?(@all_relations) do
        def __relation_opts__(name) do
          Map.get(__relation__(name), :opts, [])
        end
      end

      @all_assets Enum.reverse(@assets) ++
                    Brando.Trait.get_assets(@attrs, @assets, @relations, @traits)
      def __assets__ do
        @all_assets
      end

      for asset <- @all_assets do
        def __asset__(unquote(asset.name)) do
          unquote(Macro.escape(asset))
        end
      end

      unless Enum.empty?(@all_assets) do
        def __asset_opts__(name) do
          Map.get(__asset__(name), :opts, [])
        end
      end

      @all_traits Enum.reverse(@traits)
      def __traits__, do: @all_traits

      for {trait, trait_opts} <- @all_traits do
        def has_trait(unquote(trait)), do: true
      end

      def has_trait(_), do: false

      @required_attrs Brando.Blueprint.get_required_attrs(@all_attributes)
      @required_relations Brando.Blueprint.get_required_relations(@all_relations)
      @required_assets Brando.Blueprint.get_required_assets(@all_assets)

      @all_required_attrs @required_attrs ++ @required_relations ++ @required_assets
      def __required_attrs__ do
        @all_required_attrs
      end

      @all_optional_attrs Brando.Blueprint.get_optional_attrs(@all_attributes)
      def __optional_attrs__ do
        @all_optional_attrs
      end

      @castable_relations Brando.Blueprint.get_castable_relation_fields(@all_relations)
      def __castable_rels__ do
        @castable_relations
      end

      @castable_assets Brando.Blueprint.get_castable_asset_fields(@all_assets)
      def __castable_assets__ do
        @castable_assets
      end

      def __table_name__ do
        @table_name
      end

      def __naming__ do
        %{
          application: @application,
          domain: @domain,
          schema: @schema,
          singular: @singular,
          plural: @plural,
          table_name: @table_name,
          id: build_id(@application, @domain, @schema)
        }
      end

      def __admin_route__(type, args \\ [])

      def __admin_route__(:create, args) do
        form_path = :"admin_#{@singular}_form_path"
        base_args = [Brando.endpoint()]

        apply(
          Brando.routes(),
          form_path,
          base_args ++ [:create] ++ args
        )
      end

      def __admin_route__(:update, args) do
        form_path = :"admin_#{@singular}_form_path"
        base_args = [Brando.endpoint()]

        apply(
          Brando.routes(),
          form_path,
          base_args ++ [:update] ++ args
        )
      end

      def __modules__ do
        application_module =
          Module.concat([
            @application
          ])

        admin_module =
          Module.concat([
            :"#{@application}Admin"
          ])

        web_module =
          if @application == "Brando" do
            BrandoAdmin
          else
            Module.concat([
              :"#{@application}Web"
            ])
          end

        context_module =
          Module.concat([
            @application,
            @domain
          ])

        schema_module =
          Module.concat([
            @application,
            @domain,
            @schema
          ])

        gettext_module =
          if @gettext_module,
            do: @gettext_module,
            else:
              Module.concat([
                admin_module,
                "Gettext"
              ])

        admin_list_view =
          Module.concat([
            admin_module,
            @domain,
            "#{Macro.camelize(@singular)}ListLive"
          ])

        admin_form_view =
          Module.concat([
            admin_module,
            @domain,
            "#{Macro.camelize(@singular)}FormLive"
          ])

        %{
          application: application_module,
          context: context_module,
          schema: schema_module,
          gettext: gettext_module,
          admin_list_view: admin_list_view,
          admin_form_view: admin_form_view
        }
      end

      def __modules__(type), do: Map.get(__modules__(), type)

      @file_fields Enum.filter(@all_assets, &(&1.type == :file))
      def __file_fields__ do
        @file_fields
      end

      @image_fields Enum.filter(@all_assets, &(&1.type == :image))
      def __image_fields__ do
        @image_fields
      end

      @video_fields Enum.filter(@all_assets, &(&1.type == :video))
      def __video_fields__ do
        @video_fields
      end

      @gallery_fields Enum.filter(@all_assets, &(&1.type == :gallery))
      def __gallery_fields__ do
        @gallery_fields
      end

      @villain_fields Enum.filter(@all_relations, &(&1.opts.module == :blocks))
      def __blocks_fields__ do
        @villain_fields
      end

      @slug_fields Enum.filter(@attrs, &(&1.type == :slug))
      def __slug_fields__ do
        @slug_fields
      end

      @status_fields Enum.filter(@attrs, &(&1.type == :status))
      def __status_fields__ do
        @status_fields
      end

      if Enum.empty?(@status_fields) do
        def has_status?, do: false
      else
        def has_status?, do: true
      end

      @poly_fields Enum.filter(
                     @attrs,
                     &(&1.type in [{:array, PolymorphicEmbed}, PolymorphicEmbed])
                   )
      def __poly_fields__ do
        @poly_fields
      end

      def __translations__ do
        run_translations(__MODULE__, @translations)
      end

      def __allow_mark_as_deleted__ do
        @allow_mark_as_deleted
      end

      def __factory__(attrs) do
        Map.merge(@factory, attrs)
      end

      if @data_layer == :embedded do
        build_embedded_schema(
          __MODULE__,
          @table_name,
          @all_attributes,
          @all_relations,
          @all_assets
        )
      else
        build_schema(
          __MODULE__,
          @table_name,
          @all_attributes,
          @all_relations,
          @all_assets
        )
      end

      def __listings__ do
        @listings ++ @imported_listings
      end

      def __forms__ do
        Enum.reverse(@forms) ++ @imported_forms
      end

      def __form__ do
        Enum.find(__forms__(), &(&1.name == :default))
      end

      def __form__(name) do
        Enum.find(__forms__(), &(&1.name == name))
      end

      # generate changeset
      def changeset(schema, params \\ %{}, user \\ :system, sequence \\ nil, opts \\ []) do
        run_changeset(
          __MODULE__,
          schema,
          params,
          sequence,
          user,
          @all_traits,
          @all_attributes,
          @all_relations,
          @all_assets,
          @castable_relations,
          @castable_assets,
          @all_required_attrs,
          @all_optional_attrs,
          opts
        )
      end

      def __blueprint__ do
        %Brando.Blueprint{
          naming: __naming__(),
          modules: __modules__(),
          translations: __translations__(),
          attributes: __attributes__(),
          relations: __relations__(),
          assets: __assets__(),
          listings: __listings__(),
          form: __form__(),
          traits: __traits__()
        }
      end

      for {trait, trait_opts} <- @all_traits do
        defimpl Module.concat([trait, Implemented]) do
          def implemented(_), do: true
        end

        def __trait__(unquote(trait)) do
          unquote(trait_opts)
        end
      end

      def __trait__(_), do: false
    end
  end

  def run_changeset(
        module,
        schema,
        params,
        sequence,
        user,
        all_traits,
        all_attributes,
        all_relations,
        all_assets,
        castable_relations,
        castable_assets,
        all_required_attrs,
        all_optional_attrs,
        opts
      ) do
    start = System.monotonic_time()

    {traits_before_validate_required, traits_after_validate_required} =
      Trait.split_traits_by_changeset_phase(all_traits)

    fields_to_cast =
      (all_required_attrs ++ all_optional_attrs ++ castable_relations ++ castable_assets)
      |> strip_villains_from_fields_to_cast(module)
      |> strip_polymorphic_embeds_from_fields_to_cast(module)

    if module != schema.__struct__ do
      require Logger

      Logger.error(
        "(!) MISMATCH BETWEEN MODULE AND SCHEMA STRUCT - module which runs the changeset: #{inspect(module)}, schema struct: #{inspect(schema.__struct__)}"
      )

      Logger.error(inspect(schema, pretty: true))
    end

    changeset =
      schema
      |> Changeset.cast(params, fields_to_cast)
      |> Relations.run_cast_relations(all_relations, user)
      |> Assets.run_cast_assets(all_assets, user)
      |> Trait.run_changeset_mutators(
        module,
        traits_before_validate_required,
        user,
        opts
      )
      |> maybe_validate_required(all_required_attrs)
      |> Unique.run_unique_attribute_constraints(module, all_attributes)
      |> Unique.run_unique_relation_constraints(module, all_relations)
      |> Constraints.run_validations(module, all_attributes)
      |> Constraints.run_validations(module, all_relations)
      |> Constraints.run_fk_constraints(module, all_relations)
      |> Upload.run_upload_validations(
        module,
        all_assets,
        user
      )
      |> Trait.run_changeset_mutators(
        module,
        traits_after_validate_required,
        user,
        opts
      )
      |> maybe_mark_for_deletion(module)
      |> maybe_sequence(module, sequence)

    :telemetry.execute(
      [:brando, :run_changeset],
      %{
        duration: System.monotonic_time() - start
      },
      %{schema: changeset.data.__struct__}
    )

    changeset
  end

  def maybe_sequence(changeset, _module, nil) do
    changeset
  end

  def maybe_sequence(changeset, module, sequence) do
    if module.has_trait(Brando.Trait.Sequenced) do
      Changeset.change(changeset, sequence: sequence)
    else
      changeset
    end
  end

  def maybe_validate_required(changeset, all_required_attrs) do
    case Changeset.get_field(changeset, :status) do
      :draft -> changeset
      _ -> Changeset.validate_required(changeset, all_required_attrs)
    end
  end

  defmacro query(arg) do
    quote generated: true, location: :keep do
      case Module.get_attribute(__MODULE__, :brando_macro_context) do
        :form ->
          Brando.Blueprint.Forms.form_query(unquote(arg))

        :listing ->
          Brando.Blueprint.Listing.listing_query(unquote(arg))

        _ ->
          raise Brando.Exception.BlueprintError,
            message: "query/1 can only be used inside of listing or form declarations"
      end
    end
  end

  defp maybe_mark_for_deletion(%{changes: %{marked_as_deleted: true}} = changeset, module) do
    if module.__allow_mark_as_deleted__ do
      %{changeset | action: :delete}
    else
      changeset
    end
  end

  defp maybe_mark_for_deletion(changeset, _) do
    changeset
  end

  defp strip_villains_from_fields_to_cast(fields_to_cast, module) do
    villain_fields = Enum.map(module.__blocks_fields__(), & &1.name)
    Enum.reject(fields_to_cast, &(&1 in villain_fields))
  end

  defp strip_polymorphic_embeds_from_fields_to_cast(fields_to_cast, module) do
    poly_fields = Enum.map(module.__poly_fields__(), & &1.name)
    Enum.reject(fields_to_cast, &(&1 in poly_fields))
  end

  @doc """
  Return a list of preloads for a given schema
  """
  def preloads_for(schema) do
    asset_preloads = Brando.Blueprint.Assets.preloads_for(schema)
    rel_preloads = Brando.Blueprint.Relations.preloads_for(schema)
    blocks_preloads = Brando.Villain.preloads_for(schema)
    alternates_preload = Brando.Content.AlternateEntries.preloads_for(schema)
    identifiers_preloads = Brando.Content.Identifier.preloads_for(schema)

    Enum.uniq(
      asset_preloads ++
        rel_preloads ++
        blocks_preloads ++
        alternates_preload ++
        identifiers_preloads
    )
  end

  def blueprint?(module), do: {:__blueprint__, 0} in module.__info__(:functions)

  @doc """
  List all blueprints
  """
  @spec list_blueprints :: [module()]
  def list_blueprints do
    {:ok, app_modules} = :application.get_key(Brando.otp_app(), :modules)

    app_modules
    |> Enum.uniq()
    |> Enum.filter(&__MODULE__.blueprint?/1)
  end

  def list_blueprints(:include_brando) do
    list_blueprints() ++ [Brando.Pages.Page, Brando.Pages.Fragment]
  end

  def get_plural(module) do
    plural = Brando.Utils.try_path(module.__translations__(), [:naming, :plural])
    String.capitalize(plural || module.__naming__().plural)
  end

  defmacro import_forms(forms_module_ast) do
    env = __CALLER__

    forms_module_ast
    |> Macro.expand(env)
    |> do_import_forms(env)
  end

  defmacro import_listings(listings_module_ast) do
    env = __CALLER__

    listings_module_ast
    |> Macro.expand(env)
    |> do_import_listings(env)
  end

  defp do_import_forms({{:., _, [{:__MODULE__, _, _}, :{}]}, _, modules_ast_list}, env) do
    for {_, _, leaf} <- modules_ast_list do
      type_module = Module.concat([env.module | leaf])

      do_import_forms(type_module, env)
    end
  end

  defp do_import_forms(
         {{:., _, [{:__aliases__, _, [{:__MODULE__, _, _} | tail]}, :{}]}, _, modules_ast_list},
         env
       ) do
    root_module = Module.concat([env.module | tail])

    for {_, _, leaf} <- modules_ast_list do
      type_module = Module.concat([root_module | leaf])

      do_import_forms(type_module, env)
    end
  end

  defp do_import_forms({{:., _, [{:__aliases__, _, root}, :{}]}, _, modules_ast_list}, env) do
    root_module = Module.concat(root)
    root_module_with_alias = Keyword.get(env.aliases, root_module, root_module)

    for {_, _, leaf} <- modules_ast_list do
      type_module = Module.concat([root_module_with_alias | leaf])

      do_import_forms(type_module, env)
    end
  end

  defp do_import_forms(module, env) do
    Module.put_attribute(env.module, :__brando_imported_form_modules__, [
      module | Module.get_attribute(env.module, :__brando_imported_form_modules__) || []
    ])

    []
  end

  defp do_import_listings({{:., _, [{:__MODULE__, _, _}, :{}]}, _, modules_ast_list}, env) do
    for {_, _, leaf} <- modules_ast_list do
      type_module = Module.concat([env.module | leaf])

      do_import_listings(type_module, env)
    end
  end

  defp do_import_listings(
         {{:., _, [{:__aliases__, _, [{:__MODULE__, _, _} | tail]}, :{}]}, _, modules_ast_list},
         env
       ) do
    root_module = Module.concat([env.module | tail])

    for {_, _, leaf} <- modules_ast_list do
      type_module = Module.concat([root_module | leaf])

      do_import_listings(type_module, env)
    end
  end

  defp do_import_listings({{:., _, [{:__aliases__, _, root}, :{}]}, _, modules_ast_list}, env) do
    root_module = Module.concat(root)
    root_module_with_alias = Keyword.get(env.aliases, root_module, root_module)

    for {_, _, leaf} <- modules_ast_list do
      type_module = Module.concat([root_module_with_alias | leaf])

      do_import_listings(type_module, env)
    end
  end

  defp do_import_listings(module, env) do
    Module.put_attribute(env.module, :__brando_imported_listing_modules__, [
      module | Module.get_attribute(env.module, :__brando_imported_listing_modules__) || []
    ])

    []
  end

  defmacro __after_compile__(env, _) do
    # validate traits
    Enum.each(env.module.__traits__(), &elem(&1, 0).validate(env.module, elem(&1, 1)))
  end
end

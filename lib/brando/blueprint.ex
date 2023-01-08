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
      import unquote(__MODULE__).Meta
      import unquote(__MODULE__).Naming
      import unquote(__MODULE__).Relations
      import unquote(__MODULE__).Trait
      import unquote(__MODULE__).Translations
      import unquote(__MODULE__).Utils

      import Brando.Utils.Schema

      def __absolute_url__(_) do
        false
      end

      defoverridable __absolute_url__: 1
    end
  end

  defmacro build_attrs(attrs) do
    quote do
      Enum.map(unquote(attrs), fn
        %{name: :inserted_at} ->
          Ecto.Schema.timestamps()

        %{name: :updated_at} ->
          []

        %{type: :villain} = attr ->
          Ecto.Schema.field(
            attr.name,
            to_ecto_type(:villain),
            to_ecto_opts(attr.type, attr.opts) ++
              [
                types: Brando.Villain.Blocks.list_blocks(),
                type_field: :type,
                on_type_not_found: :raise,
                on_replace: :delete
              ]
          )

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

        %{type: :has_many, name: :alternates, opts: %{module: :alternates}} ->
          main_module = unquote(module)
          alternate_module = Module.concat([main_module, Alternate])

          [
            Ecto.Schema.has_many(
              :alternates,
              alternate_module,
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
            to_ecto_opts(:embeds_one, opts) ++ [on_replace: :update]
          )

        %{type: :embeds_many, name: name, opts: opts} ->
          Ecto.Schema.embeds_many(
            name,
            Map.fetch!(opts, :module),
            to_ecto_opts(:embeds_many, opts)
          )

        %{type: :entries, name: name, opts: opts} ->
          Ecto.Schema.embeds_many(
            name,
            Brando.Content.Identifier,
            to_ecto_opts(:embeds_many, opts) ++ [on_replace: :delete]
          )

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

        %Asset{type: :gallery_images, name: name} ->
          Ecto.Schema.has_many(
            name,
            Brando.Images.GalleryImage,
            preload_order: [asc: :sequence],
            on_replace: :delete_if_exists
          )

        asset ->
          require Logger
          Logger.error("==> asset type not caught, #{inspect(asset, pretty: true)}")
      end)
    end
  end

  defmacro build_schema(module, name, attrs, relations, assets) do
    quote location: :keep do
      schema unquote(name) do
        build_attrs(unquote(attrs))
        build_assets(unquote(assets))
        build_relations(unquote(module), unquote(relations))
      end
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

  defmacro __before_compile__(env) do
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
            imported_listings: imported_listings
          ],
          unquote: false do
      @imported_forms List.flatten(imported_forms)
      @imported_listings List.flatten(imported_listings)

      def __primary_key__ do
        @primary_key
      end

      def __admin_url__(entry) do
        modules = __modules__()

        case Code.ensure_loaded(modules.admin_update_view) do
          {:module, _} ->
            Brando.routes().admin_live_path(
              Brando.endpoint(),
              modules.admin_update_view,
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

      def __modules__ do
        application_module =
          Module.concat([
            @application
          ])

        admin_module =
          if @application == "Brando" do
            BrandoAdmin
          else
            Module.concat([
              :"#{@application}Admin"
            ])
          end

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
            "#{Recase.to_pascal(@singular)}ListLive"
          ])

        admin_create_view =
          Module.concat([
            admin_module,
            @domain,
            "#{Recase.to_pascal(@singular)}CreateLive"
          ])

        admin_update_view =
          Module.concat([
            admin_module,
            @domain,
            "#{Recase.to_pascal(@singular)}UpdateLive"
          ])

        %{
          application: application_module,
          context: context_module,
          schema: schema_module,
          gettext: gettext_module,
          admin_list_view: admin_list_view,
          admin_create_view: admin_create_view,
          admin_update_view: admin_update_view
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

      @villain_fields Enum.filter(@attrs, &(&1.type == :villain))
      def __villain_fields__ do
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
                     &(&1.type in [{:array, Brando.PolymorphicEmbed}, Brando.PolymorphicEmbed])
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
      def changeset(schema, params \\ %{}, user \\ :system, opts \\ []) do
        run_changeset(
          __MODULE__,
          schema,
          params,
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
      |> Changeset.validate_required(all_required_attrs)
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

    :telemetry.execute(
      [:brando, :run_changeset],
      %{
        duration: System.monotonic_time() - start
      },
      %{schema: changeset.data.__struct__}
    )

    changeset
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
      # setting this to delete triggers an Ecto error:
      #
      # (RuntimeError) cannot delete related <embedded_struct> because it already
      # exists and it is not currently associated with the given struct.
      # Ecto forbids casting existing records through the association field
      # for security reasons. Instead, set the foreign key value accordingly
      #
      # So we IGNORE instead, and enum through the changeset...
      %{changeset | action: :ignore}
    else
      changeset
    end
  end

  defp maybe_mark_for_deletion(changeset, _) do
    changeset
  end

  defp strip_villains_from_fields_to_cast(fields_to_cast, module) do
    villain_fields = Enum.map(module.__villain_fields__(), & &1.name)
    Enum.reject(fields_to_cast, &(&1 in villain_fields))
  end

  defp strip_polymorphic_embeds_from_fields_to_cast(fields_to_cast, module) do
    poly_fields = Enum.map(module.__poly_fields__(), & &1.name)
    Enum.reject(fields_to_cast, &(&1 in poly_fields))
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

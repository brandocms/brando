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

  import Brando.Blueprint.Utils

  alias Brando.Blueprint.Assets
  alias Brando.Blueprint.Assets.Asset
  alias Brando.Blueprint.Constraints
  alias Brando.Blueprint.Relations
  alias Brando.Blueprint.Unique
  alias Brando.Blueprint.Upload
  alias Brando.Blueprint.Villain
  alias Brando.Trait
  alias Ecto.Changeset

  defstruct naming: %{},
            modules: %{},
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
    Module.register_attribute(__CALLER__.module, :router_scope, accumulate: false)
    Module.put_attribute(__CALLER__.module, :router_scope, Keyword.get(opts, :router_scope))

    gettext_module =
      case Macro.expand(Keyword.get(opts, :gettext_module), __CALLER__) do
        nil ->
          Module.concat([:"#{Keyword.fetch!(opts, :application)}Admin", Gettext])

        module ->
          module
      end

    Module.register_attribute(__CALLER__.module, :gettext_module, accumulate: false)
    Module.put_attribute(__CALLER__.module, :gettext_module, gettext_module)

    Module.register_attribute(__CALLER__.module, :traits, accumulate: true)
    Module.register_attribute(__CALLER__.module, :table_name, accumulate: false)
    Module.register_attribute(__CALLER__.module, :data_layer, accumulate: false)
    Module.register_attribute(__CALLER__.module, :primary_key, accumulate: false, persist: true)
    Module.register_attribute(__CALLER__.module, :allow_mark_as_deleted, accumulate: false)
    Module.register_attribute(__CALLER__.module, :factory, accumulate: false)

    quote location: :keep do
      use Ecto.Schema
      use Gettext, backend: unquote(gettext_module)
      use Brando.Blueprint.Dsl

      import Brando.Blueprint
      import Brando.Blueprint.AbsoluteURL
      import Brando.Blueprint.Assets
      import Brando.Blueprint.Attributes
      import Brando.Blueprint.Forms
      import Brando.Blueprint.Identifier
      import Brando.Blueprint.Listings
      import Brando.Blueprint.Listings.Components
      import Brando.Blueprint.Naming
      import Brando.Blueprint.Relations
      import Brando.Blueprint.Trait
      import Brando.Blueprint.Translations
      import Brando.Blueprint.Utils
      import Brando.Utils.Schema
      import Ecto.Changeset
      import Phoenix.Component, except: [form: 1]

      require PolymorphicEmbed

      @data_layer :database
      @allow_mark_as_deleted false
      @factory %{}

      if String.downcase(@domain) == String.downcase(@plural) do
        @table_name "#{@plural}"
      else
        @table_name "#{String.downcase(@domain)}_#{@plural}"
      end

      def __blueprint__, do: true
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
              |> Ecto.Changeset.cast(attrs, [:parent_id, :identifier_id])
              |> Ecto.Changeset.change(sequence: sequence)
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

            alias Brando.Content.Block

            schema "#{parent_table_name}_#{blocks_rel.name}" do
              Ecto.Schema.belongs_to(:entry, parent_module)
              Ecto.Schema.belongs_to(:block, Block, on_replace: :update)
              Ecto.Schema.field(:sequence, :integer)
              Ecto.Schema.field(:marked_as_deleted, :boolean, default: false, virtual: true)
            end

            @parent_table_name parent_table_name
            def changeset(entry_block, attrs, user, recursive? \\ false) do
              entry_block
              |> Ecto.Changeset.cast(attrs, [:entry_id, :block_id, :sequence])
              |> Block.maybe_cast_recursive(recursive?, user)
              |> Ecto.Changeset.unique_constraint([:entry, :block],
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
      Brando.Blueprint.maybe_build_related_identifiers_modules(
        unquote(module),
        unquote(name),
        unquote(relations)
      )

      schema unquote(name) do
        Brando.Blueprint.build_attrs(unquote(attrs))
        Brando.Blueprint.build_assets(unquote(assets))
        Brando.Blueprint.build_relations(unquote(module), unquote(relations))
      end

      Brando.Blueprint.maybe_build_blocks_modules(
        unquote(module),
        unquote(name),
        unquote(relations)
      )
    end
  end

  defmacro build_embedded_schema(module, _name, attrs, relations, assets) do
    quote location: :keep do
      embedded_schema do
        Brando.Blueprint.build_attrs(unquote(attrs))
        Brando.Blueprint.build_assets(unquote(assets))
        Brando.Blueprint.build_relations(unquote(module), unquote(relations))
      end
    end
  end

  def get_castable_relation_fields(rels) do
    rels
    |> Enum.filter(&(&1.type == :belongs_to))
    |> Enum.map(&(&1.name |> to_string() |> Kernel.<>("_id") |> String.to_atom()))
  end

  def get_castable_asset_fields(rels) do
    rels
    |> Enum.filter(&(&1.type in [:file, :image, :video, :gallery]))
    |> Enum.map(&(&1.name |> to_string() |> Kernel.<>("_id") |> String.to_atom()))
  end

  def get_relation_key(%{type: :belongs_to, name: name}), do: :"#{name}_id"
  def get_relation_key(%{type: :file, name: name}), do: :"#{name}_id"
  def get_relation_key(%{type: :image, name: name}), do: :"#{name}_id"
  def get_relation_key(%{type: :video, name: name}), do: :"#{name}_id"
  def get_relation_key(%{type: :many_to_many, name: name}), do: name
  def get_relation_key(%{type: _, name: name}), do: name

  def run_translations(module, translations, ctx \\ nil) do
    gettext_module = module.__modules__(:gettext)
    %{domain: domain, schema: schema} = module.__naming__()
    gettext_domain = String.downcase("#{domain}_#{schema}")

    Enum.map(translations, fn
      {key, value} when is_map(value) ->
        {key, run_translations(module, value, ctx || key)}

      {key, value} ->
        {key, Gettext.dgettext(gettext_module, gettext_domain, value)}
    end)
  end

  def build_id(application, domain, schema) do
    Enum.map_join([application, domain, schema], "-", &String.downcase/1)
  end

  defmacro factory(map) do
    quote do
      @factory unquote(map)
    end
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
        castable_fields,
        required_castable_fields,
        opts
      ) do
    start = System.monotonic_time()

    # TODO: split those as module attrs maybe? we shouldn't have to parse these each time
    {traits_before_validate_required, traits_after_validate_required} =
      Trait.split_traits_by_changeset_phase(all_traits)

    if module != schema.__struct__ do
      require Logger

      Logger.error(
        "(!) MISMATCH BETWEEN MODULE AND SCHEMA STRUCT - module which runs the changeset: #{inspect(module)}, schema struct: #{inspect(schema.__struct__)}"
      )

      Logger.error(inspect(schema, pretty: true))
    end

    changeset =
      schema
      |> Changeset.cast(params, castable_fields)
      |> Relations.run_cast_relations(all_relations, user)
      |> Assets.run_cast_assets(all_assets, user)
      |> Villain.maybe_cast_blocks(module, user, opts)
      |> Trait.run_changeset_mutators(module, traits_before_validate_required, user, opts)
      |> maybe_validate_required(required_castable_fields)
      |> Unique.run_unique_attribute_constraints(module, all_attributes)
      |> Unique.run_unique_relation_constraints(module, all_relations)
      |> Constraints.run_validations(module, all_attributes)
      |> Constraints.run_validations(module, all_relations)
      |> Constraints.run_fk_constraints(module, all_relations)
      |> Upload.run_upload_validations(module, all_assets, user)
      |> Trait.run_changeset_mutators(module, traits_after_validate_required, user, opts)
      |> maybe_mark_for_deletion(module)
      |> maybe_sequence(module, sequence)

    :telemetry.execute([:brando, :run_changeset], %{duration: System.monotonic_time() - start}, %{
      schema: changeset.data.__struct__
    })

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

  defp maybe_mark_for_deletion(%Ecto.Changeset{changes: %{marked_as_deleted: true}} = changeset, module) do
    if module.__allow_mark_as_deleted__() do
      %{changeset | action: :delete}
    else
      changeset
    end
  end

  defp maybe_mark_for_deletion(changeset, _) do
    changeset
  end

  @doc """
  Return a list of preloads for a given schema
  """
  def preloads_for(schema, opts \\ []) do
    skip_blocks? = Keyword.get(opts, :skip_blocks, false)
    blocks_preloads = (skip_blocks? && []) || Brando.Villain.preloads_for(schema)
    asset_preloads = Brando.Blueprint.Assets.preloads_for(schema)
    rel_preloads = Brando.Blueprint.Relations.preloads_for(schema)
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

  def get_singular(module) do
    singular = Brando.Utils.try_path(module.__translations__(), [:naming, :singular])
    String.capitalize(singular || module.__naming__().singular)
  end

  def get_plural(module) do
    plural = Brando.Utils.try_path(module.__translations__(), [:naming, :plural])
    String.capitalize(plural || module.__naming__().plural)
  end

  # TODO: some deprecated functions — remove before 1.0
  defmacro inputs_for(_, _, _) do
    IO.warn("inputs_for/3 is deprecated. Migrate with mix brando.migrate.54")
  end

  defmacro form_query(_) do
    IO.warn("form_query/1 is deprecated. use query/1 instead. Migrate with mix brando.migrate.54")
  end

  defmacro listing_query(_) do
    IO.warn("listing_query/1 is deprecated. use query/1 instead. Migrate with mix brando.migrate.54")
  end

  defmacro filters(_) do
    IO.warn("filters/1 is deprecated. use filter/1 instead. Migrate with mix brando.migrate.54")
  end

  defmacro actions(_) do
    IO.warn("actions/1 is deprecated. use action/1 instead. Migrate with mix brando.migrate.54")
  end

  defmacro actions(_, _) do
    IO.warn(
      "actions/2 is deprecated. use action/1 instead with default_actions <bool>. Migrate with mix brando.migrate.54"
    )
  end

  defmacro field(_name, _type, _opts \\ []) do
    IO.warn("field/3 is deprecated. use component/1 instead. Migrate with mix brando.migrate.54")
  end

  defmacro template(_template, _opts \\ []) do
    IO.warn("template/2 is deprecated. use component/1 instead. Migrate with mix brando.migrate.54")
  end

  defmacro __after_compile__(env, _) do
    # validate traits
    Enum.each(env.module.__traits__(), &elem(&1, 0).validate(env.module, elem(&1, 1)))
  end
end

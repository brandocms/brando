defmodule Brando.Blueprint.Dsl do
  @moduledoc false
  use Spark.Dsl,
    default_extensions: [
      extensions: [
        Brando.Blueprint.Attributes.Dsl,
        Brando.Blueprint.Relations.Dsl,
        Brando.Blueprint.Assets.Dsl,
        Brando.Blueprint.JSONLD.Dsl,
        Brando.Blueprint.Meta.Dsl,
        Brando.Blueprint.Forms.Dsl,
        Brando.Blueprint.Listings.Dsl,
        Brando.Blueprint.Datasources.Dsl,
        Brando.Blueprint.Translations.Dsl
      ]
    ],
    opts_to_document: []

  def extract_absolute_url_preloads(module) do
    absolute_url_type = Module.get_attribute(module, :absolute_url_type)
    absolute_url_tpl = Module.get_attribute(module, :absolute_url_tpl)
    relations = Module.get_attribute(module, :relations)

    all_relations = relations

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

  @impl Spark.Dsl
  def handle_before_compile(_opts) do
    quote location: :keep, unquote: false do
      alias Brando.Exception.BlueprintError
      alias Spark.Dsl.Extension, as: SDE

      @required_attrs SDE.get_persisted(__MODULE__, :required_attrs, [])
      @optional_attrs SDE.get_persisted(__MODULE__, :optional_attrs, [])
      @attrs Enum.reverse(SDE.get_entities(__MODULE__, [:attributes]))

      @required_relations SDE.get_persisted(__MODULE__, :required_relations, [])
      @optional_relations SDE.get_persisted(__MODULE__, :optional_relations, [])
      @castable_relations SDE.get_persisted(__MODULE__, :castable_relations, [])
      @castable_required_relations SDE.get_persisted(__MODULE__, :castable_required_relations, [])
      @relations SDE.get_entities(__MODULE__, [:relations])

      @required_assets SDE.get_persisted(__MODULE__, :required_assets, [])
      @optional_assets SDE.get_persisted(__MODULE__, :optional_assets, [])
      @castable_assets SDE.get_persisted(__MODULE__, :castable_assets, [])
      @castable_required_assets SDE.get_persisted(__MODULE__, :castable_required_assets, [])
      @assets SDE.get_entities(__MODULE__, [:assets])

      # collect fields
      @castable_fields @required_attrs ++
                         @optional_attrs ++ @castable_relations ++ @castable_assets
      @required_castable_fields @required_attrs ++
                                  @castable_required_relations ++ @castable_required_assets

      @datasources SDE.get_entities(__MODULE__, [:datasources])
      @translations SDE.get_persisted(__MODULE__, :translations)

      if @datasources != [] do
        def __datasource__ do
          true
        end
      end

      @absolute_url_preloads Brando.Blueprint.Dsl.extract_absolute_url_preloads(__MODULE__)
      def __absolute_url_preloads__ do
        @absolute_url_preloads
      end

      def __primary_key__ do
        @primary_key
      end

      @all_traits Enum.reverse(@traits)
      {traits_before_validate_required, traits_after_validate_required} =
        Brando.Trait.split_traits_by_changeset_phase(@all_traits)
      @traits_before_validate_required traits_before_validate_required
      @traits_after_validate_required traits_after_validate_required
      
      def __traits__, do: @all_traits
      def __traits_before_validate_required__, do: @traits_before_validate_required
      def __traits_after_validate_required__, do: @traits_after_validate_required

      for {trait, _trait_opts} <- @all_traits do
        def has_trait(unquote(trait)), do: true
      end

      def has_trait(_), do: false

      def __required_attrs__ do
        @required_attrs
      end

      def __optional_attrs__ do
        @optional_attrs
      end

      def __required_relations__ do
        @required_relations
      end

      def __castable_relations__ do
        @castable_relations
      end

      def __required_assets__ do
        @required_assets
      end

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

      def __admin_route__(:list, args) do
        live_path =
          if @router_scope do
            :"admin_#{@router_scope}_live_path"
          else
            :admin_live_path
          end

        base_args = [Brando.endpoint()]

        apply(
          Brando.routes(),
          live_path,
          base_args ++ args
        )
      end

      def __admin_route__(:create, args) do
        form_path =
          if @router_scope do
            :"admin_#{@router_scope}_#{@singular}_form_path"
          else
            :"admin_#{@singular}_form_path"
          end

        base_args = [Brando.endpoint()]

        apply(
          Brando.routes(),
          form_path,
          base_args ++ [:create] ++ args
        )
      end

      def __admin_route__(:update, args) do
        form_path =
          if @router_scope do
            :"admin_#{@router_scope}_#{@singular}_form_path"
          else
            :"admin_#{@singular}_form_path"
          end

        base_args = [Brando.endpoint()]
        full_args = base_args ++ [:update] ++ args

        apply(
          Brando.routes(),
          form_path,
          full_args
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

      @file_fields Enum.filter(@assets, &(&1.type == :file))
      def __file_fields__ do
        @file_fields
      end

      @image_fields Enum.filter(@assets, &(&1.type == :image))
      def __image_fields__ do
        @image_fields
      end

      @video_fields Enum.filter(@assets, &(&1.type == :video))
      def __video_fields__ do
        @video_fields
      end

      @gallery_fields Enum.filter(@assets, &(&1.type == :gallery))
      def __gallery_fields__ do
        @gallery_fields
      end

      @villain_fields Enum.filter(@relations, &(&1.opts.module == :blocks))
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

      @poly_fields Enum.filter(
                     @attrs,
                     &(&1.type in [{:array, PolymorphicEmbed}, PolymorphicEmbed])
                   )
      def __poly_fields__ do
        @poly_fields
      end

      if Enum.empty?(@status_fields) do
        def has_status?, do: false
      else
        def has_status?, do: true
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
        Brando.Blueprint.build_embedded_schema(
          __MODULE__,
          @table_name,
          @attrs,
          @relations,
          @assets
        )
      else
        Brando.Blueprint.build_schema(
          __MODULE__,
          @table_name,
          @attrs,
          @relations,
          @assets
        )
      end

      def __listings__ do
        SDE.get_entities(__MODULE__, [:listings])
      end

      def __forms__ do
        SDE.get_entities(__MODULE__, [:forms])
      end

      def __form__ do
        Enum.find(__forms__(), &(&1.name == :default))
      end

      def __form__(name) do
        Enum.find(__forms__(), &(&1.name == name))
      end

      # generate changeset
      def changeset(schema, params \\ %{}, user \\ :system, sequence \\ nil, opts \\ []) do
        params = %Brando.Blueprint.ChangesetParams{
          module: __MODULE__,
          schema: schema,
          params: params,
          sequence: sequence,
          user: user,
          traits_before_validate_required: @traits_before_validate_required,
          traits_after_validate_required: @traits_after_validate_required,
          attributes: @attrs,
          relations: @relations,
          assets: @assets,
          castable_fields: @castable_fields,
          required_castable_fields: @required_castable_fields,
          opts: opts
        }
        
        run_changeset(params)
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
end

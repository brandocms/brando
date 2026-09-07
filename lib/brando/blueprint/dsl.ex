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
    type = Module.get_attribute(module, :absolute_url_type)
    tpl = Module.get_attribute(module, :absolute_url_tpl)
    relations = Module.get_attribute(module, :relations)
    extract_template_preloads(type, tpl, relations)
  end

  def extract_identifier_preloads(module) do
    type = Module.get_attribute(module, :identifier_type)
    tpl = Module.get_attribute(module, :identifier_tpl)
    relations = Module.get_attribute(module, :relations)
    extract_template_preloads(type, tpl, relations)
  end

  defp extract_template_preloads(nil, _template, _relations), do: []

  defp extract_template_preloads(:liquid, template, relations) do
    ~r/.*?(entry[.a-zA-Z0-9_]+).*?/
    |> Regex.scan(template || "", capture: :all_but_first)
    |> Enum.map(fn [path] -> String.split(path, ".") end)
    |> Enum.flat_map(fn
      [_entry, relation | _nested_fields] -> [relation]
      _direct_field -> []
    end)
    |> resolve_relation_names(relations)
  end

  defp extract_template_preloads(:i18n, template, relations) do
    template
    |> Enum.flat_map(fn
      [relation, _field | _nested_fields] -> [relation]
      _direct_field -> []
    end)
    |> resolve_relation_names(relations)
  end

  defp extract_template_preloads(:heex, template, relations) do
    ~r/@entry\.([a-zA-Z_]+)/
    |> Regex.scan(template || "", capture: :all_but_first)
    |> Enum.map(fn [relation] -> relation end)
    |> resolve_relation_names(relations)
  end

  defp resolve_relation_names(names, relations) do
    names
    |> Enum.map(&resolve_relation_name(&1, relations))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp resolve_relation_name(name, relations) when is_atom(name) do
    Enum.find_value(relations, &if(&1.name == name, do: &1.name))
  end

  defp resolve_relation_name(name, relations) when is_binary(name) do
    Enum.find_value(relations, &if(Atom.to_string(&1.name) == name, do: &1.name))
  end

  @impl Spark.Dsl
  @doc false
  def handle_before_compile(_opts) do
    [
      generated_state(),
      generated_preload_metadata(),
      generated_traits(),
      generated_blueprint_metadata(),
      generated_admin_routes(),
      generated_modules(),
      generated_asset_fields(),
      generated_schema_fields(),
      generated_schema(),
      generated_forms(),
      generated_rich_text_fields(),
      generated_changeset(),
      generated_trait_implementations()
    ]
    |> Enum.flat_map(&generated_expressions/1)
    |> then(&{:__block__, [], &1})
  end

  defp generated_expressions({:__block__, _metadata, expressions}), do: expressions
  defp generated_expressions(expression), do: [expression]

  defp generated_state do
    quote location: :keep, unquote: false do
      alias Brando.Blueprint
      alias Brando.RuntimeConfig
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
    end
  end

  defp generated_preload_metadata do
    quote location: :keep, unquote: false do
      if @datasources != [] do
        def __datasource__ do
          true
        end
      end

      @absolute_url_preloads Brando.Blueprint.Dsl.extract_absolute_url_preloads(__MODULE__)
      def __absolute_url_preloads__ do
        @absolute_url_preloads
      end

      @identifier_preloads Brando.Blueprint.Dsl.extract_identifier_preloads(__MODULE__)
      def __identifier_preloads__ do
        @identifier_preloads
      end

      def __primary_key__ do
        @primary_key
      end
    end
  end

  defp generated_traits do
    quote location: :keep, unquote: false do
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

        trait_key = trait |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()
        def has_trait(unquote(trait_key)), do: true
      end

      def has_trait(_), do: false
    end
  end

  defp generated_blueprint_metadata do
    quote location: :keep, unquote: false do
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
    end
  end

  defp generated_admin_routes do
    quote location: :keep, unquote: false do
      def __admin_route__(type, args \\ [])

      def __admin_route__(:list, args) do
        live_path =
          if @router_scope do
            :"admin_#{@router_scope}_live_path"
          else
            :admin_live_path
          end

        base_args = [RuntimeConfig.endpoint()]

        apply(
          RuntimeConfig.router_helpers(),
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

        base_args = [RuntimeConfig.endpoint()]

        apply(
          RuntimeConfig.router_helpers(),
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

        base_args = [RuntimeConfig.endpoint()]
        full_args = base_args ++ [:update] ++ args

        apply(
          RuntimeConfig.router_helpers(),
          form_path,
          full_args
        )
      end
    end
  end

  defp generated_modules do
    quote location: :keep, unquote: false do
      def __modules__ do
        application_module = Module.concat([@application])

        admin_module =
          if application_module == RuntimeConfig.get(:app_module) do
            RuntimeConfig.get(:admin_module) || Module.concat([:"#{@application}Admin"])
          else
            Module.concat([:"#{@application}Admin"])
          end

        context_module = Module.concat([@application, @domain])
        schema_module = Module.concat([@application, @domain, @schema])

        gettext_module = @gettext_module

        admin_list_view =
          Module.concat([admin_module, @domain, "#{Macro.camelize(@singular)}ListLive"])

        admin_form_view =
          Module.concat([admin_module, @domain, "#{Macro.camelize(@singular)}FormLive"])

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
    end
  end

  defp generated_asset_fields do
    quote location: :keep, unquote: false do
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
    end
  end

  defp generated_schema_fields do
    quote location: :keep, unquote: false do
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
    end
  end

  defp generated_schema do
    quote location: :keep, unquote: false do
      def __translations__ do
        run_translations(__MODULE__, @translations)
      end

      def __allow_mark_as_deleted__ do
        @allow_mark_as_deleted
      end

      def __data_layer__ do
        @data_layer
      end

      def __factory__(attrs) do
        Map.merge(@factory, attrs)
      end

      if @data_layer == :embedded do
        Blueprint.build_embedded_schema(
          __MODULE__,
          @table_name,
          @attrs,
          @relations,
          @assets
        )
      else
        Blueprint.build_schema(
          __MODULE__,
          @table_name,
          @attrs,
          @relations,
          @assets
        )
      end

      maybe_define_schema_type()
    end
  end

  defp generated_forms do
    quote location: :keep, unquote: false do
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
    end
  end

  defp generated_rich_text_fields do
    quote location: :keep, unquote: false do
      def __rich_text_fields__ do
        case __form__() do
          %{tabs: tabs} ->
            for tab <- tabs,
                fieldset <- tab.fields,
                field <- fieldset.fields,
                name <- extract_rich_text_names(field),
                do: name

          _ ->
            []
        end
      end

      defp extract_rich_text_names(%Brando.Blueprint.Forms.Input{type: :rich_text, name: name}),
        do: [name]

      defp extract_rich_text_names(%Brando.Blueprint.Forms.Subform{sub_fields: sub_fields}),
        do: Enum.flat_map(sub_fields, &extract_rich_text_names/1)

      defp extract_rich_text_names(_), do: []
    end
  end

  defp generated_changeset do
    quote location: :keep, unquote: false do
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

        Blueprint.run_changeset(params)
      end
    end
  end

  defp generated_trait_implementations do
    quote location: :keep, unquote: false do
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

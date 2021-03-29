defmodule Brando.Blueprint do
  alias Ecto.Changeset

  alias Brando.Blueprint.Relations
  alias Brando.Blueprint.Upload
  alias Brando.Blueprint.Unique
  alias Brando.Blueprint.Constraints
  alias Brando.Blueprint.Villain
  alias Brando.Trait

  defstruct naming: %{},
            modules: %{},
            translations: [],
            attributes: [],
            relations: [],
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

    Module.register_attribute(__CALLER__.module, :ctx, accumulate: false)
    Module.put_attribute(__CALLER__.module, :ctx, nil)

    quote location: :keep do
      Module.register_attribute(__MODULE__, :json_ld_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :json_ld_schema, accumulate: false)
      Module.register_attribute(__MODULE__, :meta_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :traits, accumulate: true)
      Module.register_attribute(__MODULE__, :attrs, accumulate: true)
      Module.register_attribute(__MODULE__, :relations, accumulate: true)
      Module.register_attribute(__MODULE__, :translations, accumulate: false)
      Module.register_attribute(__MODULE__, :table_name, accumulate: false)
      @translations %{}
      @table_name "#{String.downcase(@domain)}_#{@plural}"

      @before_compile Brando.Blueprint
      @after_compile Brando.Blueprint

      use Ecto.Schema

      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]

      import unquote(__MODULE__)
      import unquote(__MODULE__).AbsoluteURL
      import unquote(__MODULE__).Attributes
      import unquote(__MODULE__).Identifier
      import unquote(__MODULE__).JSONLD
      import unquote(__MODULE__).Meta
      import unquote(__MODULE__).Naming
      import unquote(__MODULE__).Relations
      import unquote(__MODULE__).Trait
      import unquote(__MODULE__).Translations

      import Brando.Utils.Schema

      def __absolute_url__(_) do
        false
      end

      defoverridable __absolute_url__: 1
    end
  end

  defmacro build_schema(name, attrs, relations) do
    quote location: :keep do
      schema unquote(name) do
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

        Enum.map(unquote(relations), fn
          %{type: :belongs_to, name: name, opts: opts} ->
            Ecto.Schema.belongs_to(
              name,
              Map.fetch!(opts, :module)
            )

          %{type: :many_to_many, name: name, opts: opts} ->
            Ecto.Schema.many_to_many(
              name,
              Map.fetch!(opts, :module),
              to_ecto_opts(:many_to_many, opts)
            )

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

          attr ->
            require Logger
            Logger.error("==> relation type not caught")
            Logger.error(inspect(attr, pretty: true))
        end)
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
  end

  def get_required_relations(rels) do
    rels
    |> Enum.filter(&Map.get(&1.opts, :required))
    |> Enum.map(&get_relation_key/1)
  end

  def get_relation_key(%{type: :belongs_to, name: name}), do: :"#{name}_id"

  def access_key(key) do
    fn
      :get, data, next ->
        next.(Keyword.get(data, key, []))

      :get_and_update, data, next ->
        value = Keyword.get(data, key, [])

        case next.(value) do
          {get, update} -> {get, Keyword.put(data, key, update)}
          :pop -> {value, Keyword.delete(data, key)}
        end
    end
  end

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

  defmacro table(table_name) do
    quote do
      @table_name unquote(table_name)
    end
  end

  defmacro __before_compile__(_) do
    quote location: :keep,
          unquote: false do
      @all_attributes Enum.reverse(@attrs) ++
                        Brando.Trait.get_attributes(@attrs, @relations, @traits)
      def __attributes__ do
        @all_attributes
      end

      for attr <- @all_attributes do
        def __attribute__(unquote(attr.name)) do
          unquote(Macro.escape(attr))
        end
      end

      unless Enum.empty?(@all_attributes) do
        def __attribute_opts__(name) do
          Map.get(__attribute__(name), :opts, [])
        end
      end

      @all_relations Enum.reverse(@relations) ++
                       Brando.Trait.get_relations(@attrs, @relations, @traits)
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

      def has_trait(key), do: key in @traits

      @all_traits Enum.reverse(@traits)
      def __traits__, do: @all_traits

      @required_attrs Brando.Blueprint.get_required_attrs(@all_attributes)
      @required_relations Brando.Blueprint.get_required_relations(@all_relations)

      @all_required_attrs @required_attrs ++ @required_relations
      def __required_attrs__ do
        @all_required_attrs
      end

      @all_optional_attrs Brando.Blueprint.get_optional_attrs(@all_attributes)
      def __optional_attrs__ do
        @all_optional_attrs
      end

      def __naming__ do
        %{
          application: @application,
          domain: @domain,
          schema: @schema,
          singular: @singular,
          plural: @plural
        }
      end

      def __modules__ do
        application_module =
          Module.concat([
            @application
          ])

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
          Module.concat([
            @application,
            "Gettext"
          ])

        %{
          application: application_module,
          context: context_module,
          schema: schema_module,
          gettext: gettext_module
        }
      end

      def __modules__(type), do: Map.get(__modules__(), type)

      @villain_fields Enum.filter(@attrs, &(&1.type == :villain))
      def __villain_fields__ do
        @villain_fields
      end

      @image_fields Enum.filter(@attrs, &(&1.type == :image))
      def __image_fields__ do
        @image_fields
      end

      @file_fields Enum.filter(@attrs, &(&1.type == :file))
      def __file_fields__ do
        @file_fields
      end

      @video_fields Enum.filter(@attrs, &(&1.type == :video))
      def __video_fields__ do
        @video_fields
      end

      @slug_fields Enum.filter(@attrs, &(&1.type == :slug))
      def __slug_fields__ do
        @slug_fields
      end

      def __translations__ do
        run_translations(__MODULE__, @translations)
      end

      build_schema(
        @table_name,
        @all_attributes,
        @all_relations
      )

      # generate changeset
      def changeset(schema, params \\ %{}, user \\ :system) do
        run_changeset(
          __MODULE__,
          schema,
          params,
          user,
          @all_traits,
          @all_attributes,
          @all_relations,
          @all_required_attrs,
          @all_optional_attrs
        )
      end

      def __blueprint__ do
        %Brando.Blueprint{
          naming: __naming__(),
          modules: __modules__(),
          translations: __translations__(),
          attributes: __attributes__(),
          relations: __relations__(),
          traits: __traits__()
        }
      end

      for {trait, trait_opts} <- @all_traits do
        defimpl Module.concat([trait, Implemented]),
          for: __MODULE__ do
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
        all_required_attrs,
        all_optional_attrs
      ) do
    {traits_before_validate_required, traits_after_validate_required} =
      Trait.split_traits_by_changeset_phase(all_traits)

    schema
    |> Changeset.cast(params, all_required_attrs ++ all_optional_attrs)
    |> Relations.run_cast_relations(all_relations, user)
    |> Trait.run_changeset_mutators(
      module,
      traits_before_validate_required,
      user
    )
    |> Changeset.validate_required(all_required_attrs)
    |> Unique.run_unique_constraints(module, all_attributes)
    |> Constraints.run_validations(module, all_attributes)
    |> Trait.run_changeset_mutators(
      module,
      traits_after_validate_required,
      user
    )
    |> Upload.run_upload_validations(module, all_attributes, user)
  end

  defmacro __after_compile__(env, _) do
    # validate traits
    Enum.each(env.module.__traits__(), &elem(&1, 0).validate(env.module, elem(&1, 1)))
  end
end

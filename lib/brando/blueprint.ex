defmodule Brando.Blueprint do
  alias Ecto.Changeset

  alias Brando.Blueprint.Relations
  alias Brando.Blueprint.Upload
  alias Brando.Blueprint.Unique
  alias Brando.Blueprint.Validations
  alias Brando.Blueprint.Villain
  alias Brando.Trait

  defmacro __using__(_) do
    quote location: :keep do
      Module.register_attribute(__MODULE__, :traits, accumulate: true)
      Module.register_attribute(__MODULE__, :attrs, accumulate: true)
      Module.register_attribute(__MODULE__, :relations, accumulate: true)
      Module.register_attribute(__MODULE__, :translations, accumulate: true)

      @before_compile Brando.Blueprint
      @after_compile Brando.Blueprint

      use Ecto.Schema
      use Brando.JSONLD.Schema

      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]

      import unquote(__MODULE__)
      import unquote(__MODULE__).Trait
      import unquote(__MODULE__).Attributes
      import unquote(__MODULE__).Relations
      import unquote(__MODULE__).Naming
      import unquote(__MODULE__).Translations
      import unquote(__MODULE__).Identifier

      import Brando.Utils.Schema

      def __absolute_url__(_) do
        false
      end
    end
  end

  defmacro build_schema(name, attrs, relations) do
    quote do
      schema unquote(name) do
        Enum.map(unquote(attrs), fn
          %{type: :villain, name: :data} = attr ->
            [
              Ecto.Schema.field(
                attr.name,
                to_ecto_type(attr.type),
                to_ecto_opts(attr.type, attr.opts)
              ),
              Ecto.Schema.field(:html, :string)
            ]

          %{type: :villain, name: name} = attr ->
            html_attr =
              name
              |> to_string
              |> String.replace("_data", "_html")
              |> String.to_atom()

            [
              Ecto.Schema.field(
                name,
                to_ecto_type(attr.type),
                to_ecto_opts(attr.type, attr.opts)
              ),
              Ecto.Schema.field(:"#{html_attr}", :string)
            ]

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

        Ecto.Schema.timestamps()
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

  defmacro __before_compile__(_) do
    quote location: :keep do
      @all_attributes Enum.reverse(@attrs) ++ Brando.Trait.get_attributes(@traits)
      def __attributes__ do
        @all_attributes
      end

      def __attribute_opts__(attr) do
        @all_attributes
        |> Enum.find(&(&1.name == attr))
        |> Map.get(:opts, [])
      end

      @all_relations Enum.reverse(@relations) ++ Brando.Trait.get_relations(@traits)
      def __relations__ do
        @all_relations
      end

      if Module.get_attribute(__MODULE__, :domain) == nil, do: raise("Missing domain/1")
      if Module.get_attribute(__MODULE__, :plural) == nil, do: raise("Missing plural/1")

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

        %{
          application: application_module,
          context: context_module,
          schema: schema_module
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

      build_schema(
        "#{String.downcase(@domain)}_#{@plural}",
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
    |> Validations.run_validations(module, all_attributes)
    |> Trait.run_changeset_mutators(
      module,
      traits_after_validate_required,
      user
    )
    |> Upload.run_upload_validations(module, all_attributes, user)
  end

  defmacro __after_compile__(env, _) do
    # validate traits
    Enum.each(
      env.module.__traits__,
      & &1.validate(env.module, env.module.__trait__(&1))
    )
  end
end

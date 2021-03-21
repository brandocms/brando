defmodule Brando.Blueprint do
  defmacro __using__(_) do
    quote location: :keep do
      # Module.register_attribute(__MODULE__, :traits, accumulate: true)
      @traits []

      @before_compile Brando.Blueprint

      import unquote(__MODULE__)
      import unquote(__MODULE__).Trait
      import unquote(__MODULE__).DataLayer
      import unquote(__MODULE__).Naming
      import unquote(__MODULE__).Translations

      use Ecto.Schema
      use Brando.JSONLD.Schema

      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]
      import Brando.Utils.Schema

      # generate changeset
      def test_changeset(schema, params \\ %{}, user \\ :system) do
        schema
        # @required_attrs ++ @optional_attrs
        |> cast(params, __required_attrs__() ++ __optional_attrs__())
        # |> cast_assoc(:properties)
        |> Brando.Trait.run_changeset_mutators(__MODULE__, __traits__(), user)

        # |> validate_required(@required_fields)
        # |> avoid_field_collision([:uri], &filter_by_language/1)
        # |> unique_constraint([:uri, :language])
        # |> validate_upload({:image, :meta_image}, user)
        # |> generate_html()
      end
    end
  end

  def build_attr(attr) do
    quote do
      field unquote(attr.name), unquote(attr.type)
    end
  end

  def build_relation(%{type: :belongs_to, opts: opts, name: name}) do
    quote do
      belongs_to unquote(name), unquote(opts.module)
    end
  end

  defmacro build_schema(name, attrs, relations) do
    quote do
      schema unquote(name) do
        Enum.map(unquote(attrs), fn
          attr ->
            Ecto.Schema.field(attr.name, to_ecto_type(attr.type))
        end)

        Enum.map(unquote(relations), fn
          %{type: :belongs_to, name: name, opts: opts} ->
            Ecto.Schema.belongs_to(name, Keyword.fetch!(opts, :module))

          attr ->
            require Logger
            Logger.error(inspect(attr, pretty: true))
        end)
      end
    end
  end

  def get_required_attrs(attrs) do
    attrs
    |> Enum.filter(&Keyword.get(&1.opts, :required))
    |> Enum.map(& &1.name)
  end

  def get_optional_attrs(attrs) do
    attrs
    |> Enum.reject(&Keyword.get(&1.opts, :required))
    |> Enum.map(& &1.name)
  end

  def get_required_relations(rels) do
    rels
    |> Enum.filter(&Keyword.get(&1.opts, :required))
    |> Enum.map(&get_relation_key/1)
  end

  def get_relation_key(%{type: :belongs_to, name: name}), do: :"#{name}_id"

  defmacro __before_compile__(_) do
    quote location: :keep do
      @all_attributes Enum.reverse(@attrs) ++ Brando.Trait.get_attributes(@traits)
      def __attributes__ do
        @all_attributes
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

      @optional_attrs Brando.Blueprint.get_optional_attrs(@all_attributes)
      def __optional_attrs__ do
        @optional_attrs
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
        Enum.reverse(@attrs) ++ Brando.Trait.get_attributes(@traits),
        Enum.reverse(@relations) ++ Brando.Trait.get_relations(@traits)
      )
    end
  end
end

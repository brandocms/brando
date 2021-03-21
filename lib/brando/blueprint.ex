defmodule Brando.Blueprint do
  defmacro __using__(_) do
    quote location: :keep do
      require Logger
      Logger.error("==> setting @traits []")
      @traits []
      @attributes []
      @relations []

      @before_compile Brando.Blueprint

      import unquote(__MODULE__)
      import unquote(__MODULE__).Trait
      import unquote(__MODULE__).Naming
      import unquote(__MODULE__).Translations

      use Ecto.Schema
      use Brando.JSONLD.Schema

      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]
      import Brando.Utils.Schema

      def __relations__, do: []
      defoverridable __relations__: 0

      def __modules__ do
        application_module =
          Module.concat([
            apply(__MODULE__, :__application__, [])
          ])

        context_module =
          Module.concat([
            apply(__MODULE__, :__application__, []),
            apply(__MODULE__, :__domain__, [])
          ])

        schema_module =
          Module.concat([
            apply(__MODULE__, :__application__, []),
            apply(__MODULE__, :__domain__, []),
            apply(__MODULE__, :__schema__, [])
          ])

        %{
          application: application_module,
          context: context_module,
          schema: schema_module
        }
      end

      def __modules__(type), do: Map.get(__modules__(), type)

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
          %{type: :slug, name: name, opts: opts} ->
            Ecto.Schema.field(name, :string)

          %{type: :datetime, name: name, opts: opts} ->
            Ecto.Schema.field(name, :utc_datetime)

          attr ->
            Ecto.Schema.field(attr.name, attr.type)
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
    quote do
      if Module.get_attribute(__MODULE__, :domain) == nil, do: raise("Missing domain/1")
      if Module.get_attribute(__MODULE__, :plural) == nil, do: raise("Missing plural/1")

      def has_trait(key), do: key in @traits
      require Logger
      Logger.error("==> defining __traits__ :/")
      def __traits__, do: Enum.reverse(@traits)

      @required_attrs Brando.Blueprint.get_required_attrs(@attrs) ++
                        Brando.Blueprint.get_required_relations(@relations)
      def __required_attrs__ do
        @required_attrs
      end

      @optional_attrs Brando.Blueprint.get_optional_attrs(@attrs)
      def __optional_attrs__ do
        @optional_attrs
      end

      @villain_fields Enum.filter(@attrs, &(&1.type == :villain))
      def __villain_fields__ do
        @villain_fields
      end

      def __image_fields__ do
        Enum.filter(@attrs, &(&1.type == :image))
      end

      def __video_fields__ do
        Enum.filter(@attrs, &(&1.type == :video))
      end

      def __slug_fields__ do
        Enum.filter(@attrs, &(&1.type == :video))
      end

      build_schema("#{String.downcase(@domain)}_#{@plural}", @attrs, @relations)
    end
  end

  @valid_attributes [
    :array,
    :boolean,
    :date,
    :datetime,
    :decimal,
    :file,
    :float,
    :gallery,
    :image,
    :integer,
    :map,
    :slug,
    :status,
    :string,
    :text,
    :time,
    :uuid,
    :video,
    :villain
  ]
  defp validate_attr!(type) when type in @valid_attributes, do: true

  defp validate_attr!(type),
    do: raise("Unknown type `#{inspect(type)}` given in blueprint")

  defmacro attributes(do: block) do
    quote generated: true, location: :keep do
      var!(attribute_list) = []
      unquote(block)
      require Logger
      Logger.error("==> get_attributes(@traits)")
      @attrs Enum.reverse(var!(attribute_list)) ++ Brando.Trait.get_attributes(@traits)

      def __attributes__ do
        require Logger
        Logger.error("==> __attributes__() called!")
        @attrs
      end
    end
  end

  defmacro attribute(name, type, opts \\ []) do
    validate_attr!(type)

    quote location: :keep do
      field = %{
        name: unquote(name),
        type: unquote(type),
        opts: unquote(opts)
      }

      var!(attribute_list) = [field | var!(attribute_list)]
    end
  end

  defmacro relations(do: block) do
    quote location: :keep do
      var!(relations_list) = []
      unquote(block)
      require Logger
      Logger.error("==> get_relations(@traits)")
      @relations Enum.reverse(var!(relations_list)) ++ Brando.Trait.get_relations(@traits)

      def __relations__ do
        require Logger
        Logger.error("==> __relations__() called!")
        @relations
      end
    end
  end

  defmacro relation(name, type, opts \\ []) do
    quote location: :keep do
      field = %{
        name: unquote(name),
        type: unquote(type),
        opts: unquote(opts)
      }

      var!(relations_list) = [field | var!(relations_list)]
    end
  end
end

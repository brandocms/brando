defmodule Brando.Blueprint do
  import Ecto.Changeset
  import Ecto.Query

  defmacro __using__(_) do
    quote location: :keep do
      Module.register_attribute(__MODULE__, :traits, accumulate: true)
      Module.register_attribute(__MODULE__, :attrs, accumulate: true)
      Module.register_attribute(__MODULE__, :relations, accumulate: true)

      @before_compile Brando.Blueprint
      @after_compile Brando.Blueprint

      import unquote(__MODULE__)
      import unquote(__MODULE__).Trait
      import unquote(__MODULE__).Attributes
      import unquote(__MODULE__).Relations
      import unquote(__MODULE__).Naming
      import unquote(__MODULE__).Translations

      use Ecto.Schema
      use Brando.JSONLD.Schema

      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]
      import Brando.Utils.Schema
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
            Ecto.Schema.belongs_to(name, Map.fetch!(opts, :module))

          attr ->
            require Logger
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
    |> maybe_add_villain_html_fields()
    |> Enum.map(& &1.name)
  end

  def get_required_relations(rels) do
    rels
    |> Enum.filter(&Map.get(&1.opts, :required))
    |> Enum.map(&get_relation_key/1)
  end

  def get_relation_key(%{type: :belongs_to, name: name}), do: :"#{name}_id"

  defp maybe_add_villain_html_fields(attrs) do
    Enum.reduce(attrs, attrs, fn attr, updated_attrs ->
      if attr.type == :villain do
        html_attr =
          attr.name
          |> to_string
          |> String.replace("data", "html")
          |> String.to_atom()

        [%{name: html_attr, opts: [], type: :text} | updated_attrs]
        # updated_attrs
      else
        updated_attrs
      end
    end)
  end

  def run_cast_relations(changeset, relations, user) do
    Enum.reduce(relations, changeset, fn rel, cs -> run_cast_relation(rel, cs, user) end)
  end

  def run_cast_relation(
        %{type: :belongs_to, opts: %{cast: true, module: _module, name: name}},
        changeset,
        _user
      ) do
    cast_assoc(changeset, name)
  end

  def run_cast_relation(
        %{type: :belongs_to, opts: %{cast: :with_user, module: module, name: name}},
        changeset,
        user
      ) do
    cast_assoc(changeset, name, with: {module, :changeset, [user]})
  end

  def run_cast_relation(
        %{type: :belongs_to, opts: %{cast: cast_opts, name: name}},
        changeset,
        user
      ) do
    case Keyword.get(cast_opts, :with) do
      {with_mod, with_fun, with_user: true} ->
        cast_assoc(changeset, name, with: {with_mod, with_fun, [user]})

      {with_mod, with_fun} ->
        cast_assoc(changeset, name, with: {with_mod, with_fun, []})
    end
  end

  def run_cast_relation(%{type: :belongs_to}, updated_changeset, _user) do
    updated_changeset
  end

  def run_unique_constraints(changeset, module, attributes) do
    attributes
    |> Enum.filter(&Map.get(&1.opts, :unique, false))
    |> Enum.reduce(changeset, fn
      %{opts: %{unique: true}} = f, new_changeset ->
        unique_constraint(new_changeset, f.name)

      %{opts: %{unique: [with: with_field]}} = f, new_changeset ->
        unique_constraint(new_changeset, [f.name, with_field])

      %{opts: %{unique: [prevent_collision: true]}} = f, new_changeset ->
        new_changeset
        |> Brando.Utils.Schema.avoid_field_collision([f.name])
        |> unique_constraint(f.name)

      %{opts: %{unique: [prevent_collision: :language]}} = f, new_changeset ->
        new_changeset
        |> Brando.Utils.Schema.avoid_field_collision(module, [f.name], &filter_by_language/2)
        |> unique_constraint([f.name, :language])
    end)
  end

  def run_validations(changeset, _module, attributes) do
    attributes
    |> Enum.filter(&Map.get(&1.opts, :validate, false))
    |> Enum.reduce(changeset, fn
      %{opts: %{validate: validations}} = f, new_changeset ->
        validations_map = Enum.into(validations, %{})

        Enum.reduce(validations_map, new_changeset, fn
          {:min_length, min_length}, validated_changeset ->
            validate_length(validated_changeset, f.name, min: min_length)

          {:max_length, max_length}, validated_changeset ->
            validate_length(validated_changeset, f.name, max: max_length)

          {:length, length}, validated_changeset ->
            validate_length(validated_changeset, f.name, is: length)

          {:format, format}, validated_changeset ->
            validate_format(validated_changeset, f.name, format)

          {:acceptance, true}, validated_changeset ->
            validate_acceptance(validated_changeset, f.name)

          {:confirmation, true}, validated_changeset ->
            validate_confirmation(validated_changeset, f.name)
        end)
    end)
  end

  defp filter_by_language(module, changeset) do
    from m in module,
      where: m.language == ^get_field(changeset, :language)
  end

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
        {traits_before_validate_required, traits_after_validate_required} =
          Brando.Trait.split_traits_by_changeset_phase(@all_traits)

        schema
        |> cast(params, @all_required_attrs() ++ @all_optional_attrs())
        # |> cast_assoc(:properties)
        |> run_cast_relations(@all_relations, user)
        |> Brando.Trait.run_changeset_mutators(
          __MODULE__,
          traits_before_validate_required,
          user
        )
        |> validate_required(@all_required_attrs)
        |> run_unique_constraints(__MODULE__, @all_attributes)
        |> run_validations(__MODULE__, @all_attributes)
        |> Brando.Trait.run_changeset_mutators(
          __MODULE__,
          traits_after_validate_required,
          user
        )

        # |> avoid_field_collision([:uri], &filter_by_language/1)
        # |> unique_constraint([:uri, :language])
        # |> validate_upload({:image, :meta_image}, user)
      end
    end
  end

  defmacro __after_compile__(env, _) do
    # validate traits
    Enum.each(
      env.module.__traits__,
      & &1.validate(env.module, env.module.__trait__(&1))
    )
  end
end

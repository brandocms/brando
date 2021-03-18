defmodule Brando.Blueprint do
  defstruct application: nil,
            domain: nil,
            schema: nil,
            meta: %{},
            identifier_fn: nil,
            absolute_url_fn: nil

  alias Brando.Blueprint

  defmacro __using__(_) do
    quote do
      import Brando.Blueprint
      var!(config) = %Brando.Blueprint{}
    end
  end

  defmacro blueprint(do: block) do
    quote location: :keep do
      result = unquote(block)
      str = var!(config)
      @blueprint Brando.Blueprint.process_blueprint(str)

      def __blueprint__ do
        @blueprint
      end
    end
  end

  def process_blueprint(blueprint) do
    source_module =
      Module.concat([blueprint.application, :Blueprints, blueprint.domain, blueprint.schema])

    schema_module = Module.concat([blueprint.application, blueprint.domain, blueprint.schema])
    context_module = Module.concat([blueprint.application, blueprint.domain])

    blueprint_modules = %Blueprint.Modules{
      blueprint: source_module,
      schema: schema_module,
      context: context_module
    }

    updates = %{
      modules: blueprint_modules,
      identifier_fn: &source_module.__identifier__/1,
      absolute_url_fn: &source_module.__absolute_url__/1
    }

    Map.merge(blueprint, updates)
  end

  defmacro application(value) do
    quote do
      var!(config) = Map.put(var!(config), :application, unquote(value))
    end
  end

  defmacro domain(value) do
    quote do
      var!(config) = Map.put(var!(config), :domain, unquote(value))
    end
  end

  defmacro schema(value) do
    quote do
      var!(config) = Map.put(var!(config), :schema, unquote(value))
    end
  end

  defmacro singular(value) do
    quote do
      var!(config) = Map.put(var!(config), :singular, unquote(value))
    end
  end

  defmacro plural(value) do
    quote do
      var!(config) = Map.put(var!(config), :plural, unquote(value))
    end
  end

  defmacro absolute_url(false) do
    quote do
      def __absolute_url__(_) do
        false
      end
    end
  end

  defmacro absolute_url(fun) do
    quote do
      def __absolute_url__(entry) do
        routes = Brando.helpers()
        endpoint = Brando.endpoint()

        try do
          unquote(fun).(routes, endpoint, entry)
        rescue
          _ -> nil
        end
      end
    end
  end

  defmacro identifier(false) do
    quote do
      def __identifier__(_) do
        nil
      end
    end
  end

  defmacro identifier(fun) do
    quote do
      def __identifier__(entry) do
        title = unquote(fun).(entry)
        type = __MODULE__.__blueprint__().singular
        status = Map.get(entry, :status, nil)
        absolute_url = __MODULE__.__absolute_url__(entry)
        cover = Brando.Schema.extract_cover(entry)

        %{
          id: entry.id,
          title: title,
          type: type,
          status: status,
          absolute_url: absolute_url,
          cover: cover,
          schema: __MODULE__
        }
      end
    end
  end

  defmacro data_schema(do: block) do
    quote do
      var!(macro_ctx) = :data_schema
      unquote(block)
    end
  end

  defmacro meta_schema(do: block) do
    quote do
      var!(macro_ctx) = :meta_schema
      unquote(block)
    end
  end

  defmacro field(name) do
    quote do
      if var!(macro_ctx) == :schema do
        var!(config)
      end

      if var!(macro_ctx) == :meta_schema do
        var!(config)
      end
    end
  end
end

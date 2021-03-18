defmodule Brando.Blueprint.Naming do
  defstruct application: nil,
            schema: nil,
            domain: nil,
            singular: nil,
            plural: nil

  ## Naming

  # defmacro naming(do: block) do
  #   quote generated: true, location: :keep do
  #     var!(macro_ctx) = :naming
  #     var!(naming) = %Brando.Blueprint.Naming{}
  #     unquote(block)
  #     @naming var!(naming)
  #     def __naming__ do
  #       @naming
  #     end

  #     def __naming__(key) do
  #       Map.get(@naming, key)
  #     end

  #     def __modules__ do
  #       source_module =
  #         Module.concat([@naming.application, :Blueprints, @naming.domain, @naming.schema])

  #       schema_module = Module.concat([@naming.application, @naming.domain, @naming.schema])
  #       context_module = Module.concat([@naming.application, @naming.domain])

  #       %Brando.Blueprint.Modules{
  #         blueprint: source_module,
  #         schema: schema_module,
  #         context: context_module
  #       }
  #     end

  #     def __modules__(key), do: Map.get(__modules__(), key)
  #   end
  # end

  defmacro application(value) do
    require Logger
    Logger.error("==> application")

    quote location: :keep do
      require Logger
      Logger.error("==> application quote")

      def __application__ do
        "hello!"
      end
    end
  end

  defmacro domain(value) do
    quote do
      var!(naming) = Map.put(var!(naming), :domain, unquote(value))
    end
  end

  defmacro schema(value) do
    quote do
      var!(naming) = Map.put(var!(naming), :schema, unquote(value))
    end
  end

  defmacro singular(value) do
    quote do
      var!(naming) = Map.put(var!(naming), :singular, unquote(value))
    end
  end

  defmacro plural(value) do
    quote do
      var!(naming) = Map.put(var!(naming), :plural, unquote(value))
    end
  end
end

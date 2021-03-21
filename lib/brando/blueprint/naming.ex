defmodule Brando.Blueprint.Naming do
  ## Naming

  defmacro application(value) do
    quote location: :keep do
      @application unquote(value)
      def __application__ do
        @application
      end
    end
  end

  defmacro domain(value) do
    quote location: :keep do
      @domain unquote(value)
      def __domain__ do
        @domain
      end
    end
  end

  defmacro schema(value) do
    quote location: :keep do
      @schema unquote(value)
      def __schema__ do
        @schema
      end
    end
  end

  defmacro singular(value) do
    quote location: :keep do
      @singular unquote(value)
      def __singular__ do
        @singular
      end
    end
  end

  defmacro plural(value) do
    quote location: :keep do
      @plural unquote(value)
      def __plural__ do
        @plural
      end
    end
  end
end

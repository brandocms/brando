defmodule Brando.Blueprint.Translations do
  defmacro translation(do: block) do
    quote location: :keep do
      var!(translation_map) = %{}
      unquote(block)
    end
  end

  defmacro t(ctx, do: block) do
    quote generated: true, location: :keep do
      var!(translation_ctx) = unquote(ctx)
      unquote(block)
    end
  end

  defmacro t(field, value) when is_atom(field) do
    quote generated: true, location: :keep do
      var!(translation_map) =
        put_in(
          var!(translation_map),
          Enum.map(
            var!(translation_ctx) ++ List.wrap(unquote(field)),
            &Access.key(&1, %{})
          ),
          unquote(value)
        )
    end
  end

  defmacro t(path, value) do
    quote generated: true, location: :keep do
      var!(translation_map) =
        put_in(
          var!(translation_map),
          Enum.map(
            unquote(path),
            &Access.key(&1, %{})
          ),
          unquote(value)
        )
    end
  end
end

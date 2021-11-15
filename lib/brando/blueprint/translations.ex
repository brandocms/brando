defmodule Brando.Blueprint.Translations do
  defmacro translations(do: block) do
    quote generated: true, location: :keep do
      unquote(block)
    end
  end

  defmacro context(ctx, do: block) do
    Module.put_attribute(__CALLER__.module, :ctx, ctx)

    quote generated: true, location: :keep do
      var!(translate_ctx) = unquote(ctx)
      unquote(block)
    end
  end

  defmacro translate(path, do: block) do
    quote generated: true, location: :keep do
      var!(translate_path) = List.wrap(unquote(path))
      unquote(block)
    end
  end

  defmacro translate(path, value) when is_list(path) do
    quote generated: true, location: :keep do
      translate_full_path = List.wrap(var!(translate_ctx)) ++ unquote(path)

      updated_translations =
        put_in(
          @translations,
          Enum.map(translate_full_path, &Access.key(&1, %{})),
          unquote(value)
        )

      @translations updated_translations
    end
  end

  defmacro translate(key, value) when is_atom(key) do
    quote generated: true, location: :keep do
      translate_full_path = List.wrap(var!(translate_ctx)) ++ List.wrap(unquote(key))

      updated_translations =
        put_in(
          @translations,
          Enum.map(translate_full_path, &Access.key(&1, %{})),
          unquote(value)
        )

      @translations updated_translations
    end
  end

  defmacro label(_),
    do:
      raise(Brando.Exception.BlueprintError,
        message:
          "translations label/1 has been deprecated. Use `input :title, :text, label: t(\"Title\")` instead"
      )

  defmacro placeholder(_),
    do:
      raise(Brando.Exception.BlueprintError,
        message:
          "translations label/1 has been deprecated. Use `input :title, :text, placeholder: t(\"Title\")` instead"
      )

  defmacro instructions(_),
    do:
      raise(Brando.Exception.BlueprintError,
        message:
          "translations label/1 has been deprecated. Use `input :title, :text, instructions: t(\"Title\")` instead"
      )

  def t_field(type, value) do
    # type is an atom -> :label | :placeholder | instructions
    # value is a gettext call, for instance -> gettext("Instructions")
    quote location: :keep do
      translate_full_path =
        List.wrap(var!(translate_ctx)) ++ var!(translate_path) ++ List.wrap(unquote(type))

      updated_translations =
        put_in(
          @translations,
          Enum.map(translate_full_path, &Access.key(&1, %{})),
          unquote(value)
        )

      @translations updated_translations
    end
  end

  defmacro t(msgid) do
    domain = Module.get_attribute(__CALLER__.module, :domain)
    schema = Module.get_attribute(__CALLER__.module, :schema)
    ctx = Module.get_attribute(__CALLER__.module, :ctx)
    gettext_domain = String.downcase("#{domain}_#{schema}_#{ctx}")

    quote do
      dgettext(unquote(gettext_domain), unquote(msgid))
    end
  end
end

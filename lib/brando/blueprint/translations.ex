defmodule Brando.Blueprint.Translations do
  @moduledoc """
  When translating subforms, use `t/2` and supply the blueprint for the subform:

      fieldset do
        size :full
        inputs_for :items,
          label: t("Items"),
          style: :inline,
          cardinality: :many,
          size: :full,
          default: %Item{} do
          input :status, :status, compact: true, label: :hidden
          input :title, :text, label: t("Title", Item)
          input :key, :text, monospace: true, label: t("Key", Item)
          input :url, :text, monospace: true, label: t("URL", Item)
          input :open_in_new_window, :toggle, label: t("New window?", Item)
        end
      end
  """
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
    gettext_module = Module.get_attribute(__CALLER__.module, :gettext_module)
    gettext_domain = String.downcase("#{domain}_#{schema}_#{ctx}")

    quote do
      Gettext.dgettext(unquote(gettext_module), unquote(gettext_domain), unquote(msgid))
    end
  end

  defmacro t(msgid, schema) do
    schema = Macro.expand(schema, __CALLER__)
    domain = schema.__naming__().domain
    schema = schema.__naming__().schema
    ctx = Module.get_attribute(__CALLER__.module, :ctx)
    gettext_module = Module.get_attribute(__CALLER__.module, :gettext_module)
    gettext_domain = String.downcase("#{domain}_#{schema}_#{ctx}")

    quote do
      Gettext.dgettext(unquote(gettext_module), unquote(gettext_domain), unquote(msgid))
    end
  end
end

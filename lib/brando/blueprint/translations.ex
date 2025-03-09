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

  defmacro t(msgid) do
    domain = Module.get_attribute(__CALLER__.module, :domain)
    schema = Module.get_attribute(__CALLER__.module, :schema)

    gettext_domain =
      [domain, schema]
      |> Enum.join("_")
      |> String.downcase()

    quote do
      dgettext(unquote(gettext_domain), unquote(msgid))
    end
  end

  defmacro t(msgid, schema) do
    schema = Macro.expand_literals(schema, %{__CALLER__ | function: {:t, 2}})
    domain = schema.__naming__().domain
    schema = schema.__naming__().schema

    gettext_domain =
      [domain, schema]
      |> Enum.join("_")
      |> String.downcase()

    quote do
      dgettext(unquote(gettext_domain), unquote(msgid))
    end
  end
end

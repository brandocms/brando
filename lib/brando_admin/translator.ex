defmodule BrandoAdmin.Translator do
  @moduledoc false
  defmacro __using__(_) do
    quote do
      def g(_schema, nil), do: nil
      def g(_schema, :hidden), do: :hidden

      def g(schema, msgid) do
        result =
          if Brando.Blueprint.blueprint?(schema) do
            gettext_module = schema.__modules__().gettext

            gettext_domain =
              String.downcase("#{schema.__naming__().domain}_#{schema.__naming__().schema}")

            Gettext.dgettext(gettext_module, gettext_domain, msgid)
          else
            msgid
          end

        {:safe, result}
      end

      def g(schema, _context, msgid) do
        g(schema, msgid)
      end
    end
  end
end

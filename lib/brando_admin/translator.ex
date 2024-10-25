defmodule BrandoAdmin.Translator do
  defmacro __using__(_) do
    quote do
      def g(schema, nil), do: nil
      def g(schema, :hidden), do: :hidden

      def g(schema, msgid) do
        if Brando.Blueprint.blueprint?(schema) do
          gettext_module = schema.__modules__().gettext

          gettext_domain =
            String.downcase("#{schema.__naming__().domain}_#{schema.__naming__().schema}")

          Gettext.dgettext(gettext_module, gettext_domain, msgid)
        else
          msgid
        end
      end

      def g(schema, context, msgid) do
        if Brando.Blueprint.blueprint?(schema) do
          gettext_module = schema.__modules__().gettext

          gettext_domain =
            String.downcase("#{schema.__naming__().domain}_#{schema.__naming__().schema}")

          Gettext.dgettext(gettext_module, gettext_domain, msgid)
        else
          msgid
        end
      end
    end
  end
end

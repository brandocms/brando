defmodule BrandoAdmin.Translator do
  defmacro __using__(ctx) do
    quote do
      def g(schema, msgid) do
        gettext_module = schema.__modules__().gettext

        gettext_domain =
          String.downcase(
            "#{schema.__naming__().domain}_#{schema.__naming__().schema}_#{unquote(ctx)}"
          )

        require Logger

        Logger.debug("""
        ==> Calling Gettext.dgettext
        -- gettext_module: #{inspect(gettext_module)}
        -- gettext_domain: #{inspect(gettext_domain)}
        -- msgid: #{inspect(msgid)}"
        """)

        Gettext.dgettext(gettext_module, gettext_domain, msgid)
      end
    end
  end
end

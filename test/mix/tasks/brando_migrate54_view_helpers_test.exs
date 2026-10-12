defmodule Mix.Tasks.Brando.Migrate54ViewHelpersTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate54

  @web_path "lib/lett_web.ex"
  @helpers_path "lib/lett_web/components/error_helpers.ex"

  @web """
  defmodule LettWeb do
    @moduledoc \"\"\"
    A module that keeps using definitions for controllers,
    views and so on.

    This can be used in your application as:

        use BrandoWeb, :controller
        use BrandoWeb, :view

    The definitions below will be executed for every view,
    controller, etc, so keep them short and clean, focused
    on imports, uses and aliases.

    Do NOT define functions inside the quoted expressions
    below.
    \"\"\"

    def schema do
      quote do
        use Brando.JSONLD.Schema
        use Ecto.Schema

        import Ecto
        import Ecto.Changeset
        import Ecto.Query
        import Brando.Utils.Schema
      end
    end

    def controller do
      quote do
        use Phoenix.Controller,
          namespace: LettWeb

        use Gettext,
          backend: LettWeb.Gettext

        import Brando.Plug.HTML
        import Plug.Conn

        alias LettWeb.Router.Helpers, as: Routes
      end
    end

    def migration do
      quote do
        import Brando.SoftDelete.Migration
      end
    end

    def context do
      quote do
        import Brando.Query
        import Brando.SoftDelete.Query
      end
    end

    def view do
      quote do
        use Phoenix.View,
          root: "lib/lett_web/templates",
          namespace: LettWeb

        # Import convenience functions from controllers
        import Phoenix.Controller, only: [get_csrf_token: 0, get_flash: 2, view_module: 1]

        unquote(view_helpers())
      end
    end

    def router do
      quote do
        use Phoenix.Router
        import Plug.Conn
        import Phoenix.Controller
        import Phoenix.LiveView.Router
      end
    end

    def channel do
      quote do
        use Phoenix.Channel

        alias Lett.Repo
        import Ecto
        import Ecto.Query

        use Gettext,
          backend: LettWeb.Gettext
      end
    end

    defp view_helpers do
      quote do
        # Use all HTML functionality (forms, tags, etc)
        use Phoenix.HTML
        import Phoenix.Component

        import Brando.HTML
        import Brando.Utils
        import Brando.Pages, only: [render_fragment: 2, render_fragment: 3, get_var: 2]
        import Brando.I18n.Helpers

        import LettWeb.ErrorHelpers

        use Gettext,
          backend: LettWeb.Gettext

        alias LettWeb.Router.Helpers, as: Routes
      end
    end

    @doc \"\"\"
    When used, dispatch to the appropriate controller/view/etc.
    \"\"\"
    defmacro __using__(which) when is_atom(which) do
      apply(__MODULE__, which, [])
    end
  end
  """

  @helpers """
  defmodule LettWeb.ErrorHelpers do
    @moduledoc \"\"\"
    Conveniences for translating and building error messages.
    \"\"\"

    use Phoenix.HTML

    @doc \"\"\"
    Generates tag for inlined form input errors.
    \"\"\"
    def error_tag(form, field) do
      Enum.map(Keyword.get_values(form.errors, field), fn error ->
        content_tag(:span, translate_error(error), class: "help-block")
      end)
    end

    @doc \"\"\"
    Translates an error message using gettext.
    \"\"\"
    def translate_error({msg, opts}) do
      # When using gettext, we typically pass the strings we want
      # to translate as a static argument:
      #
      #     # Translate "is invalid" in the "errors" domain
      #     dgettext("errors", "is invalid")
      #
      #     # Translate the number of files with plural rules
      #     dngettext("errors", "1 file", "%{count} files", count)
      #
      # Because the error messages we show in our forms and APIs
      # are defined inside Ecto, we need to translate them dynamically.
      # This requires us to call the Gettext module passing our gettext
      # backend as first argument.
      #
      # Note we use the "errors" domain, which means translations
      # should be written to the errors.po file. The :count option is
      # set by Ecto and indicates we should also apply plural rules.
      if count = opts[:count] do
        Gettext.dngettext(LettWeb.Gettext, "errors", msg, msg, count, opts)
      else
        Gettext.dgettext(LettWeb.Gettext, "errors", msg, opts)
      end
    end
  end
  """

  test "removes the Phoenix.View-era helpers when nothing uses them" do
    igniter = migrate(%{})

    assert source(igniter, @web_path) == """
           defmodule LettWeb do
             @moduledoc \"\"\"
             A module that keeps using definitions for controllers,
             views and so on.

             This can be used in your application as:

                 use BrandoWeb, :controller

             The definitions below will be executed for every view,
             controller, etc, so keep them short and clean, focused
             on imports, uses and aliases.

             Do NOT define functions inside the quoted expressions
             below.
             \"\"\"

             def schema do
               quote do
                 use Brando.JSONLD.Schema
                 use Ecto.Schema

                 import Ecto
                 import Ecto.Changeset
                 import Ecto.Query
                 import Brando.Utils.Schema
               end
             end

             def controller do
               quote do
                 use Phoenix.Controller,
                   namespace: LettWeb

                 use Gettext,
                   backend: LettWeb.Gettext

                 import Brando.Plug.HTML
                 import Plug.Conn

                 alias LettWeb.Router.Helpers, as: Routes
               end
             end

             def migration do
               quote do
                 import Brando.SoftDelete.Migration
               end
             end

             def context do
               quote do
                 import Brando.Query
                 import Brando.SoftDelete.Query
               end
             end

             def router do
               quote do
                 use Phoenix.Router
                 import Plug.Conn
                 import Phoenix.Controller
                 import Phoenix.LiveView.Router
               end
             end

             def channel do
               quote do
                 use Phoenix.Channel

                 alias Lett.Repo
                 import Ecto
                 import Ecto.Query

                 use Gettext,
                   backend: LettWeb.Gettext
               end
             end

             @doc \"\"\"
             When used, dispatch to the appropriate controller/view/etc.
             \"\"\"
             defmacro __using__(which) when is_atom(which) do
               apply(__MODULE__, which, [])
             end
           end
           """

    assert @helpers_path in igniter.rms

    assert_has_notice(igniter, fn notice ->
      notice =~ "Removed the Phoenix.View-era view helpers" and
        notice =~ "#{@helpers_path} (LettWeb.ErrorHelpers)" and notice =~ "#{@web_path}: `view/0` and `view_helpers/0`"
    end)

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate54.igniter()
    assert_unchanged(rerun, [@web_path])
  end

  test "rewrites `use Phoenix.HTML` when the view or the helpers are still used" do
    view = """
    defmodule LettWeb.ErrorView do
      use LettWeb, :view
    end
    """

    igniter = migrate(%{"lib/lett_web/views/error_view.ex" => view})

    refute @helpers_path in igniter.rms
    web = source(igniter, @web_path)
    assert web =~ "def view do"

    assert web =~
             "      # Use all HTML functionality (forms, tags, etc)\n      import Phoenix.HTML\n      import Phoenix.HTML.Form\n      use PhoenixHTMLHelpers\n      import Phoenix.Component\n"

    assert source(igniter, @helpers_path) =~
             "  import Phoenix.HTML\n  import Phoenix.HTML.Form\n  use PhoenixHTMLHelpers\n"

    assert_has_warning(igniter, fn warning ->
      warning =~ ~s({:phoenix_html_helpers, "~> 1.0"}) and warning =~ "#{@web_path}:97" and
        warning =~ "#{@helpers_path}:6" and warning =~ "lib/lett_web/views/error_view.ex:2: use LettWeb, :view"
    end)
  end

  test "keeps the helpers a template or another web module function uses" do
    template = "<%= LettWeb.ErrorHelpers.error_tag(f, :email) %>\n"
    igniter = migrate(%{"lib/lett_web/templates/contact/form.html.eex" => template})

    refute @helpers_path in igniter.rms
    assert_has_warning(igniter, &(&1 =~ "lib/lett_web/templates/contact/form.html.eex:1:"))

    live_view =
      String.replace(
        @web,
        "  def router do",
        "  def live_view do\n    quote do\n      unquote(view())\n    end\n  end\n\n  def router do"
      )

    igniter = migrate(%{@web_path => live_view})

    assert source(igniter, @web_path) =~ "def view do"
    assert_has_warning(igniter, &(&1 =~ "unquote(view())"))
  end

  test "keeps the view when a use of it spans lines or goes through an alias" do
    split = """
    defmodule LettWeb.ErrorView do
      use LettWeb,
          :view
    end
    """

    igniter = migrate(%{"lib/lett_web/views/error_view.ex" => split})

    refute @helpers_path in igniter.rms
    assert source(igniter, @web_path) =~ "def view do"
    assert_has_warning(igniter, &(&1 =~ "lib/lett_web/views/error_view.ex:2: use LettWeb,"))

    aliased = """
    defmodule LettWeb.PageView do
      alias LettWeb, as: Web
      use Web, :view
    end
    """

    igniter = migrate(%{"lib/lett_web/views/page_view.ex" => aliased})

    refute @helpers_path in igniter.rms
    assert source(igniter, @web_path) =~ "def view do"
    assert_has_warning(igniter, &(&1 =~ "lib/lett_web/views/page_view.ex:2: alias LettWeb, as: Web"))
  end

  test "keeps a helpers file that defines other modules too" do
    helpers = @helpers <> "\ndefmodule LettWeb.InputHelpers do\nend\n"
    igniter = migrate(%{@helpers_path => helpers})

    refute @helpers_path in igniter.rms
    assert_has_warning(igniter, &(&1 =~ "#{@helpers_path}: defines other modules too"))
  end

  test "lists other `use Phoenix.HTML`" do
    other = """
    defmodule LettWeb.LegacyHelpers do
      use Phoenix.HTML
    end
    """

    igniter = migrate(%{"lib/lett_web/legacy_helpers.ex" => other})

    assert @helpers_path in igniter.rms

    assert_has_warning(igniter, fn warning ->
      warning =~ "raises on `use Phoenix.HTML`" and warning =~ "lib/lett_web/legacy_helpers.ex:2" and
        not (warning =~ @helpers_path)
    end)
  end

  defp migrate(files) do
    [app_name: :lett, files: Map.merge(%{@web_path => @web, @helpers_path => @helpers}, files)]
    |> test_project()
    |> include_test_files()
    |> Migrate54.igniter()
  end

  defp source(igniter, path), do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  defp include_test_files(igniter) do
    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, &Igniter.include_existing_file(&2, &1))
  end
end

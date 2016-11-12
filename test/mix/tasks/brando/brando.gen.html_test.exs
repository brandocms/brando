Code.require_file "../../../support/mix_helper.exs", __DIR__

defmodule Phoenix.DupHTMLController do
end

defmodule Phoenix.DupHTMLView do
end

defmodule Mix.Tasks.Brando.Gen.HtmlTest do
  use ExUnit.Case
  import MixHelper

  setup do
    Mix.Task.clear
    :ok
  end

  test "generates html resource" do
    in_tmp "generates html resource", fn ->
      send self(), {:mix_shell_input, :prompt, "Game"}
      send self(), {:mix_shell_input, :prompt, "Pirate"}
      send self(), {:mix_shell_input, :prompt, "pirates"}
      send self(), {:mix_shell_input, :prompt,
        "name age:integer height:decimal nicks:array:text famous:boolean born_at:datetime " <>
        "secret:uuid photo:image pdf:file data:villain first_login:date " <>
        "alarm:time address:references creator:references"}
      send self(), {:mix_shell_input, :yes?, true}
      # and another one
      send self(), {:mix_shell_input, :yes?, true}
      send self(), {:mix_shell_input, :prompt, "Captain"}
      send self(), {:mix_shell_input, :prompt, "captains"}
      send self(), {:mix_shell_input, :prompt,
        "name age:integer height:decimal nicks:array:text famous:boolean born_at:datetime " <>
        "secret:uuid photo:image data:villain first_login:date " <>
        "alarm:time address:references creator:references"}
      send self(), {:mix_shell_input, :yes?, true}
      send self(), {:mix_shell_input, :yes?, false}
      Mix.Tasks.Brando.Gen.Html.run []

      assert_file "lib/game/pirate.ex", fn file ->
        assert file =~ "defmodule Brando.Pirate do"
        assert file =~ "schema \"pirates\" do"
        assert file =~ "field :photo, Brando.Type.Image"
        assert file =~ "field :pdf, Brando.Type.File"
        assert file =~ "singular: \"pirate\""
        assert file =~ "plural: \"pirates\""
        assert file =~ "born_at: gettext(\"Born at\")"
        assert file =~ "@required_fields ~w(name age height nicks famous " <>
                       "born_at secret data first_login " <>
                       "alarm creator_id address_id)"
        assert file =~ "@optional_fields ~w(photo pdf)"
        assert file =~ "use Brando.Sequence, :schema"
        assert file =~ "sequenced"
        assert file =~ "villain"
        assert file =~ "villain :biography"
        assert file =~ "generate_html()"
        assert file =~ "generate_html(:biography)"
      end

      assert_file "test/schemas/pirate_test.exs"
      assert [migration_file] =
        Path.wildcard("priv/repo/migrations/*_create_pirate.exs")

      assert_file migration_file, fn file ->
        assert file =~ "use Brando.Villain, :migration"
        assert file =~ "villain"
        assert file =~ "sequenced"
        assert file =~ "villain :biography"
      end

      assert_file "lib/web/controllers/pirate_controller.ex", fn file ->
        assert file =~ "defmodule Brando.PirateController"
        assert file =~ "use Brando.Web, :controller"
        assert file =~ "repo.all"
      end

      assert_file "lib/web/controllers/admin/pirate_controller.ex", fn file ->
        assert file =~ "defmodule Brando.Admin.PirateController"
        assert file =~ "use Brando.Admin.Web, :controller"
        assert file =~ "Repo.get!"
        assert file =~ "use Brando.Villain, [:controller"
        refute file =~ "import Brando.Backend.Gettext"
      end

      assert_file "lib/web/views/pirate_view.ex", fn file ->
        assert file =~ "defmodule Brando.PirateView do"
        assert file =~ "use Brando.Web, :view"
        assert file =~ "import Brando.Gettext"
      end

      assert_file "lib/web/menus/admin/pirate_menu.ex", fn file ->
        assert file =~ "defmodule Brando.Pirate.Menu do"
        assert file =~ "Brando.Registry.register(Brando.Pirate, [:menu])"
      end

      assert_file "lib/web/views/admin/pirate_view.ex", fn file ->
        assert file =~ "defmodule Brando.Admin.PirateView do"
        assert file =~ "use Brando.Web, :view"
      end

      assert_file "lib/web/templates/admin/pirate/edit.html.eex", fn file ->
        assert file =~ "<%= gettext(\"Edit pirate\") %>"
        assert file =~ "\"/admin/pirates/\""
      end

      assert_file "lib/web/templates/admin/pirate/index.html.eex", fn file ->
        assert file =~ "<%= gettext(\"Index - pirates\") %>"
        assert file =~ "Brando.HTML.Tablize.tablize(@conn, @pirates"
      end

      assert_file "lib/web/templates/admin/pirate/new.html.eex", fn file ->
        assert file =~ "<%= gettext(\"New pirate\") %>"
        assert file =~ "<%= PirateForm.get_form(type: :create, action: :create, params: [], changeset: @changeset) %>"
        assert file =~ "\"/admin/pirates/\""
      end

      assert_file "lib/web/templates/admin/pirate/delete_confirm.html.eex", fn file ->
        assert file =~ "<%= gettext(\"Delete pirate\") %>"
        assert file =~ "<%= Brando.HTML.Inspect.schema_repr(@record) %>"
        assert file =~ "<%= Brando.HTML.delete_form_button(:admin_pirate_path, @record) %>"
      end

      assert_file "lib/web/templates/admin/pirate/show.html.eex", fn file ->
        assert file =~ "<%= gettext(\"Show pirate\") %>"
        assert file =~ "<%= Brando.HTML.Inspect.schema(@pirate) %>"
      end
    end
  end
end

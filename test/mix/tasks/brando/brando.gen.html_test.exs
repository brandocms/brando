Code.require_file("../../../support/mix_helper.exs", __DIR__)

defmodule Phoenix.DupHTMLController do
end

defmodule Phoenix.DupHTMLView do
end

defmodule Mix.Tasks.Brando.Gen.HtmlTest do
  use ExUnit.Case
  import MixHelper

  setup do
    Mix.Task.clear()
    :ok
  end

  test "generates html resource" do
    in_tmp("generates html resource", fn ->
      send(self(), {:mix_shell_input, :prompt, "Games"})
      send(self(), {:mix_shell_input, :prompt, "Pirate"})
      send(self(), {:mix_shell_input, :prompt, "pirates"})

      send(
        self(),
        {:mix_shell_input, :prompt,
         "name age:integer height:decimal nicks:array:text famous:boolean born_at:datetime " <>
           "secret:uuid photo:image pdf:file data:villain biography:villain first_login:date " <>
           "alarm:time address:references creator:references"}
      )

      send(self(), {:mix_shell_input, :yes?, true})
      # and another one
      send(self(), {:mix_shell_input, :yes?, true})
      send(self(), {:mix_shell_input, :prompt, "Captain"})
      send(self(), {:mix_shell_input, :prompt, "captains"})

      send(
        self(),
        {:mix_shell_input, :prompt,
         "name age:integer height:decimal nicks:array:text famous:boolean born_at:datetime " <>
           "secret:uuid photo:image data:villain first_login:date " <>
           "alarm:time address:references creator:references"}
      )

      send(self(), {:mix_shell_input, :yes?, true})
      # and another one
      send(self(), {:mix_shell_input, :yes?, true})
      send(self(), {:mix_shell_input, :prompt, "PegLeg"})
      send(self(), {:mix_shell_input, :prompt, "peg_legs"})
      send(self(), {:mix_shell_input, :prompt, "name length:integer"})
      send(self(), {:mix_shell_input, :yes?, true})
      send(self(), {:mix_shell_input, :yes?, false})
      Mix.Tasks.Brando.Gen.Html.run([])

      assert_file("lib/brando/games/games.ex", fn file ->
        assert file =~ "defmodule Brando.Games do"
      end)

      assert_file("lib/brando/games/pirate.ex", fn file ->
        assert file =~ "defmodule Brando.Games.Pirate do"
        assert file =~ "schema \"games_pirates\" do"
        assert file =~ "field :photo, Brando.Type.Image"
        assert file =~ "field :pdf, Brando.Type.File"
        assert file =~ "singular: \"pirate\""
        assert file =~ "plural: \"pirates\""
        assert file =~ "born_at: gettext(\"Born at\")"

        assert file =~
                 "@required_fields ~w(name age height nicks famous born_at secret first_login alarm data biography_data creator_id address_id)"

        assert file =~ "@optional_fields ~w(photo pdf)"
        assert file =~ "use Brando.Sequence, :schema"
        assert file =~ "sequenced"
        assert file =~ "villain"
        assert file =~ "villain :biography"
        assert file =~ "generate_html()"
        assert file =~ "generate_html(:biography)"
      end)

      assert_file("lib/brando/games/games.ex", fn file ->
        assert file =~ "defmodule Brando.Games do"
        assert file =~ "alias Brando.Repo"
        assert file =~ "alias Brando.Games.Pirate"
      end)

      assert_file("test/schemas/pirate_test.exs")
      assert [migration_file] = Path.wildcard("priv/repo/migrations/*_create_pirate.exs")

      assert_file(migration_file, fn file ->
        assert file =~ "use Brando.Villain, :migration"
        assert file =~ "create table(:games_pirates)"
        assert file =~ "create index(:games_pirates, [:creator_id])"
        assert file =~ "villain"
        assert file =~ "sequenced"
        assert file =~ "villain :biography"
      end)

      assert_file("lib/brando_web/controllers/pirate_controller.ex", fn file ->
        assert file =~ "defmodule BrandoWeb.PirateController"
        assert file =~ "use BrandoWeb, :controller"
        assert file =~ "Games.list_pirates()"
      end)

      assert_file("lib/brando_web/views/pirate_view.ex", fn file ->
        assert file =~ "defmodule BrandoWeb.PirateView do"
        assert file =~ "use BrandoWeb, :view"
        assert file =~ "import BrandoWeb.Gettext"
      end)

      assert_file("assets/backend/src/views/games/CaptainCreateView.vue", fn file ->
        assert file =~
                 ~s(<router-link :disabled="!!loading" :to="{ name: 'captains' }" class="btn btn-outline-secondary">)
      end)

      assert_file("assets/backend/src/views/games/PegLegCreateView.vue", fn file ->
        assert file =~
                 ~s(<router-link :disabled="!!loading" :to="{ name: 'peg_legs' }" class="btn btn-outline-secondary">)

        assert file =~ ~s(v-model="pegLeg.name")
      end)
    end)
  end
end

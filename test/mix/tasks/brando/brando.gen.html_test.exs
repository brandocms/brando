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
    in_tmp("brando.gen.html", fn ->
      Mix.Tasks.Brando.Install.run([])

      send(self(), {:mix_shell_input, :prompt, "Games"})
      send(self(), {:mix_shell_input, :prompt, "Pirate"})
      send(self(), {:mix_shell_input, :prompt, "pirates"})

      send(
        self(),
        {:mix_shell_input, :prompt,
         "name age:integer height:decimal famous:boolean born_at:datetime " <>
           "secret:uuid cover:image pdf:file data:villain biography:villain first_login:date " <>
           "alarm:time address:references:addresses creator:references:users"}
      )

      send(self(), {:mix_shell_input, :yes?, true})
      # and another one
      send(self(), {:mix_shell_input, :yes?, true})
      send(self(), {:mix_shell_input, :prompt, "Captain"})
      send(self(), {:mix_shell_input, :prompt, "captains"})

      send(
        self(),
        {:mix_shell_input, :prompt,
         "name age:integer height:decimal famous:boolean born_at:datetime " <>
           "secret:uuid cover:image data:villain first_login:date " <>
           "alarm:time creator:references:users image_series:gallery"}
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

      assert_received {:mix_shell, :info,
                       [
                         "Update your repository by running migrations:\n    $ mix ecto.migrate\n================================================================================================\n"
                       ]}

      assert_file("lib/brando/graphql/schema.ex", fn file ->
        assert file =~ "import_fields :pirate_queries"
        assert file =~ "import_fields :pirate_mutations"
      end)

      assert_file("lib/brando/graphql/schema/types.ex", fn file ->
        assert file =~ "import_types Brando.Schema.Types.Pirate"
      end)

      assert_file("lib/brando/graphql/schema/types/pirate.ex", fn file ->
        assert file =~ "defmodule Brando.Schema.Types.Pirate do"
        assert file =~ "field :pdf, :file_type"
        assert file =~ "field :pdf, :upload"
      end)

      assert_file("lib/brando/games/games.ex", fn file ->
        assert file =~ "defmodule Brando.Games do"
      end)

      assert_file("lib/brando/games/pirate.ex", fn file ->
        assert file =~ "defmodule Brando.Games.Pirate do"
        assert file =~ "schema \"games_pirates\" do"
        assert file =~ "field :cover, Brando.Type.Image"
        assert file =~ "field :pdf, Brando.Type.File"

        assert file =~
                 "@required_fields ~w(name age height famous born_at secret " <>
                   "first_login alarm data biography_data creator_id address_id)a"

        assert file =~ "@optional_fields ~w(cover pdf)"
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
        assert file =~ "use Brando.Villain.Migration"
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

      assert_file("assets/backend/src/api/graphql/pirates/PIRATE_QUERY.graphql", fn file ->
        assert file =~ ~s(\n    pdf {\n      url\n    }\n)
      end)

      assert_file("assets/backend/src/api/graphql/captains/CAPTAIN_QUERY.graphql", fn file ->
        assert file =~
                 ~s({\n    id\n    name\n    age\n    height\n    famous\n    born_at\n    secret\n    cover {\n      thumb: url\(size: "original"\)\n      focal\n    }\n    data\n    first_login\n    alarm\n    creator\n    image_series_id\n  })
      end)

      assert_file("assets/backend/src/api/graphql/captains/CAPTAINS_QUERY.graphql", fn file ->
        assert file =~
                 ~s({\n    id\n    name\n    age\n    height\n    famous\n    born_at\n    secret\n    cover {\n      thumb: url\(size: "original"\)\n      focal\n    }\n    data\n    first_login\n    alarm\n    creator\n    image_series_id\n    updated_at\n  })
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

      assert_file("assets/backend/src/views/games/CaptainListView.vue", fn file ->
        assert file =~ ~s(v-sortable)

        assert file =~
                 "<td class=\"fit\">\n                    {{ captain.name }}\n                  </td>"

        assert file =~
                 "<td class=\"fit\">\n                    <CheckOrX :val=\"captain.famous\" />\n                  </td>"

        assert file =~
                 "<td class=\"fit\">\n                    <img\n                      v-if=\"captain.cover\"\n                      :src=\"captain.cover.thumb\"\n                      class=\"avatar-sm img-border-lg\" />\n                  </td>"
      end)
    end)
  end
end

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
           "secret:uuid cover:image pdf:file data:villain biography:villain first_login:date " <>
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
           "secret:uuid cover:image data:villain first_login:date " <>
           "alarm:time address:references creator:references image_series:gallery"}
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
                         "You must add the GraphQL types/mutations/queries to your applications schema\n`lib/brando/graphql/schema.ex`\n\n    query do\n      import_brando_queries()\n\n      # local queries\n      import_fields :pirate_queries\n    end\n\n    mutation do\n      import_brando_mutations()\n\n      # local mutations\n      import_fields :pirate_mutations\n    end\n\nAlso add the type imports to your types file\n`lib/brando/graphql/schema/types.ex`\n\n    # local imports\n    import_types Brando.Schema.Types.Pirate\n\nAdd the sequence helper to your `admin_channel`:\n\n    use Brando.Sequence, :channel\n    sequence \"pirates\", BrandoWeb.Pirate\n\n\n\n\nand then update your repository by running migrations:\n    $ mix ecto.migrate\n\n================================================================================================\nYou must add the GraphQL types/mutations/queries to your applications schema\n`lib/brando/graphql/schema.ex`\n\n    query do\n      import_brando_queries()\n\n      # local queries\n      import_fields :captain_queries\n    end\n\n    mutation do\n      import_brando_mutations()\n\n      # local mutations\n      import_fields :captain_mutations\n    end\n\nAlso add the type imports to your types file\n`lib/brando/graphql/schema/types.ex`\n\n    # local imports\n    import_types Brando.Schema.Types.Captain\n\nAdd the sequence helper to your `admin_channel`:\n\n    use Brando.Sequence, :channel\n    sequence \"captains\", BrandoWeb.Captain\n\n\nAdd this gallery helper to your `admin_channel`:\n\n    def handle_in(\"captain:create_image_series\", %{\"captain_id\" => captain_id}, socket) do\n      user = Guardian.Phoenix.Socket.current_resource(socket)\n      {:ok, image_series} = Games.create_image_series(captain_id, user)\n      {:reply, {:ok, %{code: 200, image_series: Map.merge(image_series, %{creator: nil, image_category: nil, images: nil})}}, socket}\n    end\n\n\n\nand then update your repository by running migrations:\n    $ mix ecto.migrate\n\n================================================================================================\nYou must add the GraphQL types/mutations/queries to your applications schema\n`lib/brando/graphql/schema.ex`\n\n    query do\n      import_brando_queries()\n\n      # local queries\n      import_fields :peg_leg_queries\n    end\n\n    mutation do\n      import_brando_mutations()\n\n      # local mutations\n      import_fields :peg_leg_mutations\n    end\n\nAlso add the type imports to your types file\n`lib/brando/graphql/schema/types.ex`\n\n    # local imports\n    import_types Brando.Schema.Types.PegLeg\n\nAdd the sequence helper to your `admin_channel`:\n\n    use Brando.Sequence, :channel\n    sequence \"peg_legs\", BrandoWeb.PegLeg\n\n\n\n\nand then update your repository by running migrations:\n    $ mix ecto.migrate\n\n================================================================================================\n"
                       ]}

      assert_file("lib/brando/games/games.ex", fn file ->
        assert file =~ "defmodule Brando.Games do"
      end)

      assert_file("lib/brando/games/pirate.ex", fn file ->
        assert file =~ "defmodule Brando.Games.Pirate do"
        assert file =~ "schema \"games_pirates\" do"
        assert file =~ "field :cover, Brando.Type.Image"
        assert file =~ "field :pdf, Brando.Type.File"

        assert file =~
                 "@required_fields ~w(name age height nicks famous born_at secret first_login alarm data biography_data creator_id address_id)"

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

      assert_file("assets/backend/src/api/graphql/captains/CAPTAIN_QUERY.graphql", fn file ->
        assert file =~
                 ~s({\n    id\n    name\n    age\n    height\n    nicks\n    famous\n    born_at\n    secret\n    cover {\n      thumb: url\(size: "original"\)\n      focal\n    }\n    data\n    first_login\n    alarm\n    address\n    creator\n    image_series_id\n  })
      end)

      assert_file("assets/backend/src/api/graphql/captains/CAPTAINS_QUERY.graphql", fn file ->
        assert file =~
                 ~s({\n    id\n    name\n    age\n    height\n    nicks\n    famous\n    born_at\n    secret\n    cover {\n      thumb: url\(size: "original"\)\n      focal\n    }\n    data\n    first_login\n    alarm\n    address\n    creator\n    image_series_id\n    updated_at\n  })
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

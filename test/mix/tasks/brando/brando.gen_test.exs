Code.require_file("../../../support/mix_helper.exs", __DIR__)

defmodule Phoenix.DupHTMLController do
end

defmodule Phoenix.DupHTMLView do
end

defmodule Mix.Tasks.Brando.Gen.Test do
  use ExUnit.Case
  import MixHelper

  setup do
    Mix.Task.clear()
    :ok
  end

  test "generates html resource" do
    in_tmp("brando.gen", fn ->
      Mix.Tasks.Brando.Install.run([])

      send(self(), {:mix_shell_input, :prompt, "Games"})
      send(self(), {:mix_shell_input, :prompt, "Pirate"})
      send(self(), {:mix_shell_input, :prompt, "pirates"})

      send(
        self(),
        {:mix_shell_input, :prompt,
         "name slug:slug:name age:integer height:decimal famous:boolean born_at:datetime " <>
           "secret:uuid cover:image pdf:file data:villain biography:villain first_login:date " <>
           "alarm:time address:references:addresses"}
      )

      # sequence?
      send(self(), {:mix_shell_input, :yes?, true})
      # deleted_at?
      send(self(), {:mix_shell_input, :yes?, false})
      # creator?
      send(self(), {:mix_shell_input, :yes?, true})

      Mix.Tasks.Brando.Gen.run([])

      send(self(), {:mix_shell_input, :prompt, "Games"})
      send(self(), {:mix_shell_input, :prompt, "Captain"})
      send(self(), {:mix_shell_input, :prompt, "captains"})

      send(
        self(),
        {:mix_shell_input, :prompt,
         "title age:integer height:decimal famous:boolean born_at:datetime " <>
           "secret:uuid cover:image data:villain first_login:date " <>
           "alarm:time image_series:gallery"}
      )

      # sequence?
      send(self(), {:mix_shell_input, :yes?, true})
      # deleted_at?
      send(self(), {:mix_shell_input, :yes?, false})
      # creator?
      send(self(), {:mix_shell_input, :yes?, true})

      Mix.Tasks.Brando.Gen.run([])

      # test gallery
      assert_file("lib/brando/games/captain.ex", fn file ->
        assert file =~
                 "|> cast_assoc(:image_series, with: {Brando.ImageSeries, :changeset, [user]})"

        assert file =~
                 "@required_fields ~w(title age height famous born_at secret first_login alarm creator_id data)a"

        assert file =~ "@optional_fields ~w(image_series_id cover)a"
      end)

      assert_file("assets/backend/src/views/games/CaptainEditView.vue", fn file ->
        assert file =~
                 "const captainParams = this.$utils.stripParams(\n        this.captain, [\n          '__typename',\n          'id',\n          'insertedAt',\n          'updatedAt',\n          'deletedAt',\n          'creator',\n          'imageSeries'\n        ]\n      )"
      end)

      send(self(), {:mix_shell_input, :prompt, "Games"})
      send(self(), {:mix_shell_input, :prompt, "PegLeg"})
      send(self(), {:mix_shell_input, :prompt, "peg_legs"})
      send(self(), {:mix_shell_input, :prompt, "name length:integer"})

      # sequence?
      send(self(), {:mix_shell_input, :yes?, false})
      # deleted_at?
      send(self(), {:mix_shell_input, :yes?, false})
      # creator?
      send(self(), {:mix_shell_input, :yes?, true})

      Mix.Tasks.Brando.Gen.run([])

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
                 "@required_fields ~w(name slug age height famous born_at secret first_login alarm creator_id data biography_data address_id)a"

        assert file =~ "@optional_fields ~w(cover pdf)"
        assert file =~ "use Brando.Sequence.Schema"
        assert file =~ "sequenced"
        assert file =~ "villain"
        assert file =~ "field :slug, :string"
        assert file =~ "villain :biography"
        assert file =~ "generate_html()"
        assert file =~ "generate_html(:biography)"
        assert file =~ "avoid_slug_collision()"
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
        assert file =~ "create index(:games_pirates, [:slug])"
      end)

      assert_file("lib/brando_web/controllers/pirate_controller.ex", fn file ->
        assert file =~ "defmodule BrandoWeb.PirateController"
        assert file =~ "use BrandoWeb, :controller"
        assert file =~ "Games.list_pirates(list_opts)"
      end)

      assert_file("lib/brando_web/views/pirate_view.ex", fn file ->
        assert file =~ "defmodule BrandoWeb.PirateView do"
        assert file =~ "use BrandoWeb, :view"
        assert file =~ "import BrandoWeb.Gettext"
      end)

      assert_file("assets/backend/src/gql/games/PIRATE_QUERY.graphql", fn file ->
        assert file =~
                 "#import \"./PIRATE_FRAGMENT.graphql\"\nquery Pirate($pirateId: ID!) {\n  pirate(pirateId: $pirateId) {\n    ...pirate\n  }\n}\n"
      end)

      assert_file("assets/backend/src/gql/games/CAPTAIN_QUERY.graphql", fn file ->
        assert file =~
                 "#import \"./CAPTAIN_FRAGMENT.graphql\"\nquery Captain($captainId: ID!) {\n  captain(captainId: $captainId) {\n    ...captain\n  }\n}\n"
      end)

      assert_file("assets/backend/src/gql/games/CAPTAINS_QUERY.graphql", fn file ->
        assert file =~
                 "#import \"./CAPTAIN_FRAGMENT.graphql\"\nquery Captains ($order: Order, $limit: Int, $offset: Int, $filter: CaptainFilter, $status: String) {\n  captains (order: $order, limit: $limit, offset: $offset, filter: $filter, status: $status) {\n    ...captain\n  }\n}\n"
      end)

      assert_file("assets/backend/src/views/games/CaptainForm.vue", fn file ->
        assert file =~
                 "<KForm\n    v-if=\"captain\"\n    :back=\"{ name: 'captains' }\"\n    @save=\"save\">"
      end)

      assert_file("assets/backend/src/views/games/CaptainCreateView.vue", fn file ->
        assert file =~
                 "<CaptainForm\n      :captain=\"captain\"\n      :save=\"save\" />"
      end)

      assert_file("assets/backend/src/views/games/CaptainEditView.vue", fn file ->
        assert file =~
                 ~s(this.$utils.validateImageParams\(captainParams, ['cover']\))
      end)

      assert_file("assets/backend/src/views/games/PegLegForm.vue", fn file ->
        assert file =~
                 "<KForm\n    v-if=\"pegLeg\"\n    :back=\"{ name: 'pegLegs' }\"\n    @save=\"save\">"

        assert file =~ ~s(v-model="pegLeg.name")
      end)

      assert_file("assets/backend/src/views/games/PirateForm.vue", fn file ->
        assert file =~ ~s(<KInputSlug)
        assert file =~ ~s(:from="pirate.name")
      end)

      assert_file("assets/backend/src/views/games/PegLegCreateView.vue", fn file ->
        assert file =~
                 "<PegLegForm\n      :pegLeg=\"pegLeg\"\n      :save=\"save\" />"
      end)

      assert_file("assets/backend/src/views/games/CaptainListView.vue", fn file ->
        assert file =~
                 ":sortable=\"true\"\n      @sort=\"sortEntries\"\n      :filter-keys=\"['title']\"\n"
      end)

      assert_file("assets/backend/src/views/games/CaptainListView.vue", fn file ->
        assert file =~ "sortEntries (seq)"
      end)

      send(self(), {:mix_shell_input, :prompt, "Games"})
      send(self(), {:mix_shell_input, :prompt, "Parrot"})
      send(self(), {:mix_shell_input, :prompt, "parrots"})

      send(
        self(),
        {:mix_shell_input, :prompt, "name age:integer height:decimal"}
      )

      # sequence?
      send(self(), {:mix_shell_input, :yes?, false})
      # deleted_at?
      send(self(), {:mix_shell_input, :yes?, false})
      # creator?
      send(self(), {:mix_shell_input, :yes?, true})

      Mix.Tasks.Brando.Gen.run([])

      # test with soft delete

      send(self(), {:mix_shell_input, :prompt, "Projects"})
      send(self(), {:mix_shell_input, :prompt, "Project"})
      send(self(), {:mix_shell_input, :prompt, "projects"})

      send(
        self(),
        {:mix_shell_input, :prompt,
         "heading slug status:status client:references:projects_clients"}
      )

      # sequence?
      send(self(), {:mix_shell_input, :yes?, true})
      # deleted_at?
      send(self(), {:mix_shell_input, :yes?, true})
      # creator?
      send(self(), {:mix_shell_input, :yes?, true})

      Mix.Tasks.Brando.Gen.run([])

      assert_file("lib/brando/graphql/schema/types/project.ex", fn file ->
        assert file =~ "defmodule Brando.Schema.Types.Project do"
        assert file =~ "field :heading, :string"
        assert file =~ "field :slug, :string"
        assert file =~ "field :deleted_at, :time"
        assert file =~ "field :client_id, :id"
      end)

      assert_file("lib/brando/graphql/resolvers/project_resolver.ex", fn file ->
        assert file =~ "defmodule Brando.Projects.ProjectResolver do"
      end)

      assert_file("assets/backend/src/gql/projects/PROJECTS_QUERY.graphql", fn file ->
        assert file =~
                 "#import \"./PROJECT_FRAGMENT.graphql\"\nquery Projects ($order: Order, $limit: Int, $offset: Int, $filter: ProjectFilter, $status: String) {\n  projects (order: $order, limit: $limit, offset: $offset, filter: $filter, status: $status) {\n    ...project\n  }\n}\n"
      end)
    end)
  end
end

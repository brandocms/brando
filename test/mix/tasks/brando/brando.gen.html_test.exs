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
      send self(), {:mix_shell_input, :yes?, true}
      Mix.Tasks.Brando.Gen.Html.run [
        "MinionFace", "minion_faces", "name", "age:integer", "height:decimal",
        "nicks:array:text", "famous:boolean", "born_at:datetime",
        "secret:uuid", "photo:image", "data:villain", "first_login:date",
        "alarm:time", "address:references", "creator:references"]

      assert_file "web/schemas/minion_face.ex", fn file ->
        assert file =~ "defmodule Brando.MinionFace do"
        assert file =~ "schema \"minion_faces\" do"
        assert file =~ "field :photo, Brando.Type.Image"
        assert file =~ "singular: \"minion face\""
        assert file =~ "plural: \"minion faces\""
        assert file =~ "born_at: gettext(\"Born at\")"
        assert file =~ "@required_fields ~w(name age height nicks famous " <>
                       "born_at secret data first_login " <>
                       "alarm creator_id address_id)"
        assert file =~ "@optional_fields ~w(photo)"
        assert file =~ "use Brando.Sequence, :schema"
        assert file =~ "sequenced"
      end

      assert_file "test/schemas/minion_face_test.exs"
      assert [migration_file] =
        Path.wildcard("priv/repo/migrations/*_create_minion_face.exs")

      assert_file migration_file, fn file ->
        assert file =~ "use Brando.Villain, :migration"
        assert file =~ "villain"
        assert file =~ "sequenced"
      end

      assert_file "web/controllers/minion_face_controller.ex", fn file ->
        assert file =~ "defmodule Brando.MinionFaceController"
        assert file =~ "use Brando.Web, :controller"
        assert file =~ "repo.all"
      end

      assert_file "web/controllers/admin/minion_face_controller.ex", fn file ->
        assert file =~ "defmodule Brando.Admin.MinionFaceController"
        assert file =~ "use Brando.Admin.Web, :controller"
        assert file =~ "Repo.get!"
        assert file =~ "use Brando.Villain, [:controller"
        refute file =~ "import Brando.Backend.Gettext"
      end

      assert_file "web/views/minion_face_view.ex", fn file ->
        assert file =~ "defmodule Brando.MinionFaceView do"
        assert file =~ "use Brando.Web, :view"
        assert file =~ "import Brando.Gettext"
      end

      assert_file "web/menus/admin/minion_face_menu.ex", fn file ->
        assert file =~ "defmodule Brando.MinionFace.Menu do"
        assert file =~ "Brando.Registry.register(Brando.MinionFace, [:menu])"
      end

      assert_file "web/views/admin/minion_face_view.ex", fn file ->
        assert file =~ "defmodule Brando.Admin.MinionFaceView do"
        assert file =~ "use Brando.Web, :view"
      end

      assert_file "web/templates/admin/minion_face/edit.html.eex", fn file ->
        assert file =~ "<%= gettext(\"Edit minion_face\") %>"
        assert file =~ "\"/admin/minion_faces/\""
      end

      assert_file "web/templates/admin/minion_face/index.html.eex", fn file ->
        assert file =~ "<%= gettext(\"Index - minion_faces\") %>"
        assert file =~ "Brando.HTML.Tablize.tablize(@conn, @minion_faces"
      end

      assert_file "web/templates/admin/minion_face/new.html.eex", fn file ->
        assert file =~ "<%= gettext(\"New minion_face\") %>"
        assert file =~ "<%= MinionFaceForm.get_form(type: :create, action: :create, params: [], changeset: @changeset) %>"
        assert file =~ "\"/admin/minion_faces/\""
      end

      assert_file "web/templates/admin/minion_face/delete_confirm.html.eex", fn file ->
        assert file =~ "<%= gettext(\"Delete minion_face\") %>"
        assert file =~ "<%= Brando.HTML.Inspect.schema_repr(@record) %>"
        assert file =~ "<%= Brando.HTML.delete_form_button(:admin_minion_face_path, @record) %>"
      end

      assert_file "web/templates/admin/minion_face/show.html.eex", fn file ->
        assert file =~ "<%= gettext(\"Show minion_face\") %>"
        assert file =~ "<%= Brando.HTML.Inspect.schema(@minion_face) %>"
      end
    end
  end

  test "plural can't contain a colon" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Brando.Gen.Html.run ["Admin.User", "name:string", "foo:string"]
    end
  end
end

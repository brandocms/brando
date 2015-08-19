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
      Mix.Tasks.Brando.Gen.Html.run ["MinionFace", "minion_faces", "name", "age:integer", "height:decimal",
                                      "nicks:array:text", "famous:boolean", "born_at:datetime",
                                      "secret:uuid", "photo:image", "data:villain", "first_login:date",
                                      "alarm:time", "address:references"]
                                      ++ ["--nosingular", "minjongtryne", "--noplural", "minjongtryner"]

      assert_file "web/models/minion_face.ex", fn file ->
        assert file =~ "defmodule Brando.MinionFace do"
        assert file =~ "schema \"minion_faces\" do"
        assert file =~ "field :photo, Brando.Type.Image"
        assert file =~ "singular: \"minion face\""
        assert file =~ "plural: \"minion faces\""
        assert file =~ "born_at: \"Born at\""
        assert file =~ "singular: \"minjongtryne\""
        assert file =~ "plural: \"minjongtryner\""
      end

      assert_file "test/models/minion_face_test.exs"
      assert [_] = Path.wildcard("priv/repo/migrations/*_create_minion_face.exs")

      assert_file "web/controllers/minion_face_controller.ex", fn file ->
        assert file =~ "defmodule Brando.MinionFaceController"
        assert file =~ "use Brando.Web, :controller"
        assert file =~ "repo.all"
      end

      assert_file "web/controllers/admin/minion_face_controller.ex", fn file ->
        assert file =~ "defmodule Brando.Admin.MinionFaceController"
        assert file =~ "use Brando.Web, :controller"
        assert file =~ "Repo.get!"
        assert file =~ "use Brando.Villain.Controller"
      end

      assert_file "web/views/minion_face_view.ex", fn file ->
        assert file =~ "defmodule Brando.MinionFaceView do"
        assert file =~ "use Brando.Web, :view"
      end

      assert_file "web/menus/admin/minion_face_menu.ex", fn file ->
        assert file =~ "defmodule Brando.Menu.MinionFaces do"
        assert file =~ "modules: [MinionFaces, ...]"
      end

      assert_file "web/views/admin/minion_face_view.ex", fn file ->
        assert file =~ "defmodule Brando.Admin.MinionFaceView do"
        assert file =~ "use Brando.Web, :view"
      end

      assert_file "web/templates/admin/minion_face/edit.html.eex", fn file ->
        assert file =~ "<%= t!(@language, \"actions.edit\") %>"
        assert file =~ "v = new Villain.Editor"
        assert file =~ "uploadURL: '/admin/minion_faces/villain/upload/minion_face/'"
      end

      assert_file "web/templates/admin/minion_face/index.html.eex", fn file ->
        assert file =~ "<%= t!(@language, \"actions.index\") %>"
        assert file =~ "Brando.HTML.Tablize.tablize(@conn, @minion_faces"
      end

      assert_file "web/templates/admin/minion_face/new.html.eex", fn file ->
        assert file =~ "<%= t!(@language, \"actions.new\") %>"
        assert file =~ "<%= MinionFaceForm.get_form(@language, type: :create, action: :create, params: [], changeset: @changeset) %>"
        assert file =~ "v = new Villain.Editor"
        assert file =~ "uploadURL: '/admin/minion_faces/villain/upload/minion_face/'"
      end

      assert_file "web/templates/admin/minion_face/delete_confirm.html.eex", fn file ->
        assert file =~ "<%= t!(@language, \"actions.delete\") %>"
        assert file =~ "<%= Brando.HTML.Inspect.model_repr(@language, @record) %>"
        assert file =~ "<%= Brando.HTML.delete_form_button(@language, :admin_minion_face_path, @record) %>"
      end

      assert_file "web/templates/admin/minion_face/show.html.eex", fn file ->
        assert file =~ "<%= t!(@language, \"actions.show\") %>"
        assert file =~ "<%= Brando.HTML.Inspect.model(@language, @minion_face) %>"
      end
    end
  end

  test "plural can't contain a colon" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Brando.Gen.Html.run ["Admin.User", "name:string", "foo:string"]
                                    ++ ["--nosingular", "minjongtryne", "--noplural", "minjongtryner"]
    end
  end
end
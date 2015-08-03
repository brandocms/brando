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
      Mix.Tasks.Brando.Gen.Html.run ["minion", "minions", "name", "age:integer", "height:decimal",
                                      "nicks:array:text", "famous:boolean", "born_at:datetime",
                                      "secret:uuid", "photo:image", "data:villain", "first_login:date",
                                      "alarm:time", "address:references"]
                                      ++ ["--nosingular", "minjong", "--noplural", "minjongere"]

      assert_file "web/models/minion.ex"
      assert_file "test/models/minion_test.exs"
      assert [_] = Path.wildcard("priv/repo/migrations/*_create_minion.exs")

      assert_file "web/controllers/minion_controller.ex", fn file ->
        assert file =~ "defmodule Brando.MinionController"
        assert file =~ "use Brando.Web, :controller"
        assert file =~ "repo.all"
      end

      assert_file "web/controllers/admin/minion_controller.ex", fn file ->
        assert file =~ "defmodule Brando.Admin.MinionController"
        assert file =~ "use Brando.Web, :controller"
        assert file =~ "Repo.get!"
        assert file =~ "use Brando.Villain.Controller"
      end

      assert_file "web/views/minion_view.ex", fn file ->
        assert file =~ "defmodule Brando.MinionView do"
        assert file =~ "use Brando.Web, :view"
      end

      assert_file "web/views/admin/minion_view.ex", fn file ->
        assert file =~ "defmodule Brando.Admin.MinionView do"
        assert file =~ "use Brando.Web, :view"
      end

      assert_file "web/templates/admin/minion/edit.html.eex", fn file ->
        assert file =~ "<%= t!(@language, \"actions.edit\") %>"
        assert file =~ "v = new Villain.Editor"
        assert file =~ "uploadURL: '/admin/minions/villain/upload/minion/'"
      end

      assert_file "web/templates/admin/minion/index.html.eex", fn file ->
        assert file =~ "<%= t!(@language, \"actions.index\") %>"
        assert file =~ "Brando.HTML.Tablize.tablize(@conn, @minions"
      end

      assert_file "web/templates/admin/minion/new.html.eex", fn file ->
        assert file =~ "<%= t!(@language, \"actions.new\") %>"
        assert file =~ "<%= MinionForm.get_form(@language, type: :create, action: :create, params: [], values: @changeset.params, errors: @changeset.errors) %>"
        assert file =~ "v = new Villain.Editor"
        assert file =~ "uploadURL: '/admin/minions/villain/upload/minion/'"
      end

      assert_file "web/templates/admin/minion/delete_confirm.html.eex", fn file ->
        assert file =~ "<%= t!(@language, \"actions.delete\") %>"
        assert file =~ "<%= Brando.HTML.Inspect.model_repr(@language, @record) %>"
        assert file =~ "<%= Brando.HTML.delete_form_button(@language, @record, :admin_minion_path) %>"
      end

      assert_file "web/templates/admin/minion/show.html.eex", fn file ->
        assert file =~ "<%= t!(@language, \"actions.show\") %>"
        assert file =~ "<%= Brando.HTML.Inspect.model(@language, @minion) %>"
      end
    end
  end

  # test "generates html resource without model" do
  #   in_tmp "generates html resource without model", fn ->
  #     Mix.Tasks.Phoenix.Gen.Html.run ["Admin.User", "users", "--no-model", "name:string"]

  #     refute File.exists? "web/models/admin/user.ex"
  #     assert [] = Path.wildcard("priv/repo/migrations/*_create_admin_user.exs")

  #     assert_file "web/templates/admin/user/form.html.eex", fn file ->
  #       refute file =~ ~s(--no-model)
  #     end
  #   end
  # end

  # test "plural can't contain a colon" do
  #   assert_raise Mix.Error, fn ->
  #     Mix.Tasks.Phoenix.Gen.Html.run ["Admin.User", "name:string", "foo:string"]
  #   end
  # end

  # test "name is already defined" do
  #   assert_raise Mix.Error, fn ->
  #     Mix.Tasks.Phoenix.Gen.Html.run ["DupHTML", "duphtmls"]
  #   end
  # end
end
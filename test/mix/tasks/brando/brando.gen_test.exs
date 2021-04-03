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

      send(self(), {:mix_shell_input, :prompt, "Brando.BlueprintTest.Project"})
      Mix.Tasks.Brando.Gen.run([])

      assert_file("assets/backend/src/views/projects/ProjectForm.vue", fn file ->
        assert file =~ "v-model=\"project.title\""
      end)
    end)
  end
end

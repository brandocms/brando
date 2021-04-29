Code.require_file("../../../support/mix_helper.exs", __DIR__)

defmodule Mix.Tasks.Brando.Gen.BlueprintTest do
  use ExUnit.Case
  import MixHelper

  setup do
    Mix.Task.clear()
    :ok
  end

  test "generates html resource" do
    in_tmp("brando.gen.blueprint", fn ->
      send(self(), {:mix_shell_input, :prompt, "MyDomain"})
      send(self(), {:mix_shell_input, :prompt, "MySchema"})
      Mix.Tasks.Brando.Gen.Blueprint.run([])

      # test gallery
      assert_file("lib/brando/my_domain/my_schema.ex", fn file ->
        assert file =~
                 "defmodule BrandoIntegration.MyDomain.MySchema do\n  use Brando.Blueprint,\n    application: \"BrandoIntegration\""
      end)
    end)
  end
end

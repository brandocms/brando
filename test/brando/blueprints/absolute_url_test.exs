defmodule Brando.Blueprint.AbsoluteURLTest do
  use ExUnit.Case

  test "extract_preloads_from_absolute_url" do
    assert Brando.Blueprint.AbsoluteURL.extract_preloads_from_absolute_url(
             Brando.BlueprintTest.Project
           ) == [:creator, :properties]

    assert Brando.Blueprint.AbsoluteURL.extract_preloads_from_absolute_url(Brando.Pages.Page) ==
             nil
  end
end

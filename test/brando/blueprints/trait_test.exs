defmodule Brando.Blueprint.TraitTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Trait

  describe "implementations" do
    test "list" do
      assert Enum.sort(Trait.list_implementations(Brando.Trait.SoftDelete)) == [
               Brando.BlueprintTest.Project,
               Brando.Content.Container,
               Brando.Content.Module,
               Brando.Content.Palette,
               Brando.Content.Template,
               Brando.Files.File,
               Brando.Images.Gallery,
               Brando.Images.Image,
               Brando.MigrationTest.Profile,
               Brando.MigrationTest.Project,
               Brando.Pages.Fragment,
               Brando.Pages.Page,
               Brando.Persons.Person,
               Brando.Users.User,
               Brando.Videos.Video
             ]
    end
  end
end

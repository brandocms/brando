defmodule Brando.Blueprint.UniqueFieldsTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.UniqueFields

  describe "language_scoped?/1" do
    test "a scope that includes the language" do
      assert UniqueFields.language_scoped?(prevent_collision: :language)
      assert UniqueFields.language_scoped?(prevent_collision: [:site, :language])
      assert UniqueFields.language_scoped?(prevent_collision: &Function.identity/1, with: :language)
      assert UniqueFields.language_scoped?(prevent_collision: &Function.identity/1, with: [:site, :language])
    end

    test "a table-wide or unreadable scope" do
      refute UniqueFields.language_scoped?(true)
      refute UniqueFields.language_scoped?(nil)
      refute UniqueFields.language_scoped?(prevent_collision: true)
      refute UniqueFields.language_scoped?(prevent_collision: :site)
      refute UniqueFields.language_scoped?(prevent_collision: &Function.identity/1)
    end
  end
end

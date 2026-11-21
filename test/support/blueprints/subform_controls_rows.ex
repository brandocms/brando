# The rows of the subforms BrandoAdmin.Components.Form.SubformControlsTest
# compiles: an embedded one, and one in a table of its own, sequenced.
defmodule Brando.SubformControlsTest.Row do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SubformControlsTest",
    schema: "Row",
    singular: "row",
    plural: "rows",
    gettext_module: Brando.Gettext

  data_layer :embedded
  identifier false
  persist_identifier false

  attributes do
    attribute :title, :string
  end
end

defmodule Brando.SubformControlsTest.Part do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "SubformControlsTest",
    schema: "Part",
    singular: "part",
    plural: "parts",
    gettext_module: Brando.Gettext

  identifier false
  persist_identifier false
  trait Brando.Trait.Sequenced

  attributes do
    attribute :title, :string
    attribute :holder_id, :integer
  end
end

defmodule BrandoAdmin.LiveView.Form.TransformerRoutingTest do
  # Regression coverage for the webhook -> Transformer routing in
  # `handle_hooks_video_info/2`'s 2-tuple clause. Both halves of it shipped
  # broken and neither could be seen in development:
  #
  #   * `schema.__relations__()` — `__relations__` takes the module and lives on
  #     `Brando.Blueprint.Relations`; it is not defined on the blueprint. Every
  #     other call site in the codebase gets this right. This one raised
  #     `UndefinedFunctionError` and killed the form LiveView.
  #
  #   * the component id was built as `"<singular>_form-transformer-<rel>"`,
  #     using the Form *component* id. `fieldset/field.ex` renders the component
  #     as `"#{@form.id}-transformer-#{@input.name}"` — the HTML form id, with no
  #     `_form`. That one is silent: `send_update` to an unknown id logs a miss
  #     and the card simply never updates.
  #
  # Only a provider webhook reaches this clause, so a developer with no tunnel
  # never runs it and both defects reached production intact.
  use ExUnit.Case, async: true

  alias BrandoAdmin.LiveView.Form.Hooks

  defmodule MediaItem do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Routing",
      schema: "MediaItem",
      singular: "media_item",
      plural: "media_items",
      gettext_module: Brando.Gettext

    identifier false
    persist_identifier false

    assets do
      asset :video, :video, cfg: %{upload_strategy: :mux, allowed_mimetypes: ["video/mp4"]}
    end
  end

  defmodule Slide do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Routing",
      schema: "Slide",
      singular: "slide",
      plural: "slides",
      gettext_module: Brando.Gettext

    identifier false
    persist_identifier false

    assets do
      asset :video, :video, cfg: %{upload_strategy: :mux, allowed_mimetypes: ["video/mp4"]}
    end
  end

  defmodule Unrelated do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Routing",
      schema: "Unrelated",
      singular: "unrelated",
      plural: "unrelateds",
      gettext_module: Brando.Gettext

    identifier false
    persist_identifier false
  end

  defmodule Project do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Routing",
      schema: "Project",
      singular: "project",
      plural: "projects",
      gettext_module: Brando.Gettext

    identifier false
    persist_identifier false

    attributes do
      attribute :title, :string
    end

    relations do
      relation :media_items, :has_many, module: MediaItem
      relation :slides, :has_many, module: Slide
      # belongs_to must not be routed to a transformer — it has no grid to update.
      relation :cover_item, :belongs_to, module: MediaItem
    end
  end

  describe "transformer_ids_for/2" do
    test "resolves the relation owning the schema" do
      assert Hooks.transformer_ids_for(Project, MediaItem) == ["project-transformer-media_items"]
    end

    test "uses the HTML form id, not the Form component id" do
      [id] = Hooks.transformer_ids_for(Project, MediaItem)

      # The exact string `fieldset/field.ex` renders the component under. If this
      # drifts, the webhook addresses a component that does not exist and the
      # card silently never updates.
      form_id = Project.__naming__().singular
      assert id == "#{form_id}-transformer-media_items"
      refute id =~ "_form-transformer"
    end

    test "does not route a belongs_to to a transformer" do
      # cover_item points at MediaItem too, but only the has_many owns a grid.
      assert Hooks.transformer_ids_for(Project, MediaItem) == ["project-transformer-media_items"]
    end

    test "routes each has_many that owns the schema" do
      assert Hooks.transformer_ids_for(Project, Slide) == ["project-transformer-slides"]
    end

    test "returns nothing for a schema no relation points at" do
      assert Hooks.transformer_ids_for(Project, Unrelated) == []
    end

    # The original defect in one line: `__relations__` is not on the blueprint.
    test "reads relations through Brando.Blueprint.Relations, which the blueprint does not export" do
      refute function_exported?(Project, :__relations__, 0)
      assert Brando.Blueprint.Relations.__relations__(Project) != []
    end
  end
end

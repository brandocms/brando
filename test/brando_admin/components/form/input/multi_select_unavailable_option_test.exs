defmodule BrandoAdmin.Components.Form.Input.MultiSelectUnavailableOptionTest do
  # A selected has_many row whose option is no longer offered (filtered out by
  # language or status, or its entry deleted) still shows under "Currently
  # selected". Its Remove button must carry the relation's foreign key, the
  # value the select_option handler matches on, not the join row's own id.
  use ExUnit.Case, async: false
  use Brando.ConnCase
  import Phoenix.LiveViewTest

  alias Brando.Content.ModuleSetModule
  alias BrandoAdmin.Components.Form.Input.MultiSelect
  alias Ecto.Changeset

  defmodule Host do
    use Phoenix.LiveView, layout: false

    alias Brando.Content.Module
    alias Brando.Content.ModuleSet
    alias Brando.Content.ModuleSetModule
    alias Ecto.Changeset
    alias Phoenix.Component

    # The related entry join 7 was loaded with; the options no longer offer it.
    def hero, do: %Module{id: 42, name: %{"en" => "Hero"}, namespace: %{"en" => "general"}}

    def mount(_, %{"test_pid" => test_pid}, socket) do
      # Join 7 points at module 42, which is not among the options. Join 9
      # points at module 7, which is: the unavailable row's join id is also
      # the foreign key of another selection. The unsaved join points at
      # module 43, also not offered, and has no related entry loaded.
      module_set =
        loaded(%ModuleSet{
          id: 1,
          title: "Set",
          module_set_modules: [
            loaded(%ModuleSetModule{id: 7, module_id: 42, module: hero(), module_set_id: 1, sequence: 0}),
            loaded(%ModuleSetModule{id: 9, module_id: 7, module_set_id: 1, sequence: 1})
          ]
        })

      unsaved = %ModuleSetModule{} |> Changeset.change(module_id: 43, sequence: 2) |> Map.put(:action, :insert)

      changeset =
        module_set
        |> Changeset.change()
        |> Changeset.put_assoc(:module_set_modules, module_set.module_set_modules ++ [unsaved])

      {:ok,
       socket
       |> Component.assign(:test_pid, test_pid)
       |> Component.assign(:on_change, &send(self(), {:on_change, &1}))
       |> Component.assign(:form, Component.to_form(changeset, as: "module_set"))}
    end

    def handle_info({:on_change, %{action: :update_changeset, changeset: changeset}}, socket) do
      send(socket.assigns.test_pid, {:updated_changeset, changeset})
      {:noreply, Component.assign(socket, :form, Component.to_form(changeset, as: "module_set"))}
    end

    # The mutation listener registration and the live preview relation update.
    def handle_info(_message, socket), do: {:noreply, socket}

    def render(assigns) do
      ~H"""
      <.live_component
        module={MultiSelect}
        id="modules"
        field={@form[:module_set_modules]}
        label="Modules"
        on_change={@on_change}
        opts={[
          relation_key: :module_id,
          relation: :module,
          options: [%{label: "Available module", value: "7"}]
        ]}
      />
      """
    end

    defp loaded(struct), do: Ecto.put_meta(struct, state: :loaded)
  end

  @chosen "#module_set_module_set_modules-chosen"

  defp remove_values(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(".multiselect-chosen-row button[aria-label=Remove]")
    |> Enum.flat_map(&Floki.attribute(&1, "value"))
  end

  defp module_ids(changeset) do
    changeset
    |> Changeset.get_assoc(:module_set_modules)
    |> Enum.map(&{&1.data.id, Changeset.get_field(&1, :module_id), Changeset.get_change(&1, :marked_as_deleted)})
  end

  setup %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, Host, session: %{"test_pid" => self()})
    view |> element(".multiselect > .button-edit") |> render_click()
    %{view: view}
  end

  test "an unavailable row's Remove carries its foreign key", %{view: view} do
    assert remove_values(view) == ["42", "7", "43"]
    assert has_element?(view, "#{@chosen}-42-label")
    assert has_element?(view, "#{@chosen}-43-label")
  end

  test "an unavailable row is labelled with its related entry when loaded", %{view: view} do
    title = Brando.Content.Module.__identifier__(Host.hero(), skip_cover: true).title
    assert title =~ "Hero"

    # The title leads and the secondary line marks the option as missing.
    assert has_element?(view, "#{@chosen}-42-label", title)
    assert has_element?(view, ~s(.multiselect-chosen-row[data-label="#{title}"] #{@chosen}-42-details))
    # Without a loaded entry there is nothing better than the missing label.
    refute has_element?(view, "#{@chosen}-43-label", title)
    refute has_element?(view, "#{@chosen}-43-details")
  end

  test "Remove on an unavailable persisted row deletes that selection", %{view: view} do
    view |> element(~s(.multiselect-chosen-row button[value="42"])) |> render_click()

    assert_receive {:updated_changeset, changeset}
    assert module_ids(changeset) == [{7, 42, true}, {9, 7, nil}, {nil, 43, nil}]
    assert remove_values(view) == ["7", "43"]
  end

  test "Remove on an unavailable unsaved row drops that selection", %{view: view} do
    view |> element(~s(.multiselect-chosen-row button[value="43"])) |> render_click()

    assert_receive {:updated_changeset, changeset}
    assert module_ids(changeset) == [{7, 42, nil}, {9, 7, nil}]
    assert remove_values(view) == ["42", "7"]
  end

  test "the probe's join renders its foreign key, not its id" do
    join = Changeset.change(%ModuleSetModule{id: 7, module_id: 42})

    html =
      render_component(&MultiSelect.chosen_rows/1,
        id_prefix: "audit",
        selected_options: [join],
        input_options: [],
        relation_type: :has_many,
        relation_key: :module_id,
        target: 1
      )

    assert html =~ ~s(value="42")
    refute html =~ ~s(value="7")
  end
end

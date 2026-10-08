defmodule BrandoAdmin.IdentityServicesLiveTest do
  # The services on Configuration → Identity: a listing subform, one row per
  # service, whose fields open under the row.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Sites.Identity
  alias Brando.Sites.Service

  @form "#identity_form_form"
  @field "#identity_services-field-base"

  # Saving refreshes the identity cache, which outlives the sandbox.
  setup do
    cached = Brando.Cache.get(:identity)
    on_exit(fn -> Brando.Cache.put(:identity, cached, :infinite) end)
    :ok
  end

  defp identity, do: Repo.get_by!(Identity, language: "en")

  defp services do
    Repo.all(from(s in Service, where: s.identity_id == ^identity().id, order_by: [asc: s.sequence, asc: s.id]))
  end

  defp open(conn) do
    {view, _html} = live_form(conn, "/admin/config/identity", "identity_form")
    view
  end

  # Settings forms stay on the screen after saving
  defp save(view, params \\ %{}) do
    view |> form(@form, params) |> render_submit()
    settle(view)
  end

  defp row_names(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("#{@field} .subform-summary strong")
    |> Enum.map(&String.trim(Floki.text(&1)))
  end

  defp service_params(index, attrs), do: %{"identity" => %{"services" => %{"#{index}" => attrs}}}

  defp insert_services(names) do
    names
    |> Enum.with_index()
    |> Enum.each(fn {name, sequence} ->
      Repo.insert!(%Service{identity_id: identity().id, name: name, sequence: sequence, service_type: "Consulting"})
    end)
  end

  test "a service is added, named and saved; its row sums it up", %{conn: conn} do
    view = open(conn)
    assert has_element?(view, "#{@field} .subform-list-frame .subform-empty")

    view |> element("#{@field} .subform-list-foot button", "Add entry") |> render_click()

    # A new service opens for editing, under a row that says what to do
    assert has_element?(view, "#identity_services_0-entry .subform-summary", "New service")
    assert has_element?(view, "#identity_services_0-entry .subform-summary-edit[aria-expanded=true]", "Done")
    refute has_element?(view, "#identity_services_0-fields[hidden]")

    params =
      service_params(0, %{"name" => "Brand strategy", "service_type" => "Consulting", "url" => "https://acme.test/brand"})

    view |> form(@form, params) |> render_change()
    view |> element("#identity_services_0-entry .subform-summary-edit") |> render_click()

    assert has_element?(view, "#identity_services_0-fields[hidden]")
    assert has_element?(view, "#identity_services_0-entry .subform-summary strong", "Brand strategy")
    assert has_element?(view, "#identity_services_0-entry .subform-summary .badge", "Consulting")
    assert has_element?(view, "#identity_services_0-entry .subform-summary small", "https://acme.test/brand")
    assert has_element?(view, "#{@field} .subform-table-count", "1 entry")

    save(view)
    assert [%Service{name: "Brand strategy", service_type: "Consulting", url: "https://acme.test/brand"}] = services()
  end

  test "a saved service is edited, reordered and removed", %{conn: conn} do
    insert_services(["Brand strategy", "Web design", "Workshops"])

    view = open(conn)
    assert has_element?(view, "#identity_services_2-entry .subform-summary strong", "Workshops")
    assert has_element?(view, "#identity_services_0-fields[hidden]")

    view |> element("#identity_services_1-entry .subform-summary-edit", "Edit") |> render_click()
    refute has_element?(view, "#identity_services_1-fields[hidden]")
    save(view, service_params(1, %{"name" => "Web design and development"}))

    assert Enum.map(services(), & &1.name) == ["Brand strategy", "Web design and development", "Workshops"]

    # Dragging a row sends the new order; Remove sends the row's own index
    view = open(conn)
    assert has_element?(view, "#identity_services_0-entry button.subform-handle")
    view |> element(@form) |> render_change(%{"identity" => %{"sort_services_ids" => ["2", "0", "1"]}})
    assert row_names(view) == ["Workshops", "Brand strategy", "Web design and development"]
    save(view)

    assert Enum.map(services(), & &1.name) == ["Workshops", "Brand strategy", "Web design and development"]

    view = open(conn)
    assert has_element?(view, "#identity_services_0-entry button[name='identity[drop_services_ids][]'][value='0']")
    view |> element(@form) |> render_change(%{"identity" => %{"drop_services_ids" => ["0"]}})
    assert row_names(view) == ["Brand strategy", "Web design and development"]
    save(view)

    assert Enum.map(services(), & &1.name) == ["Brand strategy", "Web design and development"]
  end
end

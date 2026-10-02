defmodule Brando.FormsTest do
  use Brando.ConnCase, async: false

  alias Brando.Factory
  alias Brando.Forms
  alias Brando.Forms.Field
  alias Brando.Forms.Form
  alias Brando.Translations

  setup do
    %{user: Factory.insert(:random_user)}
  end

  defp create_form(user, attrs \\ %{}) do
    %{
      "title" => "Kontakt",
      "key" => "contact",
      "language" => "no",
      "status" => "published",
      "fields" => [
        %{"key" => "name", "type" => "text", "label" => "Navn", "required" => "true", "width" => "half"},
        %{
          "key" => "service",
          "type" => "select",
          "label" => "Tjeneste",
          "width" => "half",
          "option_rows_present" => "1",
          "option_rows" => %{
            "0" => %{"value" => "web", "label" => "Nettside"},
            "1" => %{"value" => "brand", "label" => "Merkevare"}
          }
        }
      ]
    }
    |> Map.merge(attrs)
    |> Forms.create_form(user)
  end

  defp load(id) do
    {:ok, form} = Forms.get_form(%{matches: %{id: id}, preload: [:fields, :alternate_entries]})
    form
  end

  test "option rows become ordered values with labels by value", %{user: user} do
    {:ok, form} = create_form(user)
    [name, service] = load(form.id).fields

    assert name.option_values == []
    assert service.option_values == ["web", "brand"]
    assert service.option_labels == %{"web" => "Nettside", "brand" => "Merkevare"}
    assert Field.options(service) == [{"web", "Nettside"}, {"brand", "Merkevare"}]
    assert name.uid && service.uid && name.uid != service.uid
  end

  test "rows are ordered by index, blank values dropped and an emptied list kept empty", %{user: user} do
    {:ok, form} = create_form(user)
    [name, service] = load(form.id).fields

    rows = %{
      "10" => %{"value" => "other", "label" => ""},
      "2" => %{"value" => " brand ", "label" => "Merkevare"},
      "3" => %{"value" => "", "label" => "Uten verdi"}
    }

    {:ok, _} =
      Forms.update_form(
        form.id,
        %{
          "fields" => [
            %{"id" => name.id, "key" => "name", "type" => "text"},
            %{
              "id" => service.id,
              "key" => "service",
              "type" => "select",
              "option_rows_present" => "1",
              "option_rows" => rows
            }
          ]
        },
        user
      )

    service = Enum.find(load(form.id).fields, &(&1.key == "service"))
    assert service.option_values == ["brand", "other"]
    # A label left blank falls back to the value
    assert Field.options(service) == [{"brand", "Merkevare"}, {"other", "other"}]

    {:ok, _} =
      Forms.update_form(
        form.id,
        %{"fields" => [%{"id" => name.id}, %{"id" => service.id, "option_rows_present" => "1"}]},
        user
      )

    assert Enum.find(load(form.id).fields, &(&1.key == "service")).option_values == []
  end

  test "a field key must be usable as a parameter name", %{user: user} do
    assert {:error, changeset} =
             create_form(user, %{"fields" => [%{"key" => "Full name", "type" => "text"}]})

    [field] = changeset.changes.fields
    assert {_, [validation: :format]} = field.errors[:key]
  end

  test "two fields cannot share a key", %{user: user} do
    assert {:error, changeset} =
             create_form(user, %{
               "fields" => [%{"key" => "email", "type" => "email"}, %{"key" => "email", "type" => "text"}]
             })

    assert {message, _} = changeset.errors[:fields]
    assert message =~ "email"
  end

  test "a copy in the same language gets its own key and fresh fields", %{user: user} do
    {:ok, form} = create_form(user)
    {:ok, copy} = Forms.duplicate_form(form.id, user)

    copy = load(copy.id)
    assert copy.key == "contact_copy"
    assert Enum.map(copy.fields, & &1.key) == ["name", "service"]
    assert Enum.map(copy.fields, & &1.id) != Enum.map(load(form.id).fields, & &1.id)
  end

  describe "synchronized translation" do
    test "a translation keeps the key and pairs its fields with the source's", %{user: user} do
      {:ok, source} = create_form(user)
      assert {:ok, target} = Translations.create_target(Form, source.id, :en, user)

      source = load(source.id)
      target = load(target.id)

      assert target.key == "contact"
      assert target.language == :en
      assert Enum.map(target.fields, & &1.uid) == Enum.map(source.fields, & &1.uid)
      assert [%{id: source_id}] = target.alternate_entries
      assert source_id == source.id
    end

    test "the source decides fields and option values, the translation keeps its wording", %{user: user} do
      {:ok, source} = create_form(user)
      {:ok, target} = Translations.create_target(Form, source.id, :en, user)
      target = load(target.id)
      [t_name, t_service] = target.fields

      {:ok, _} =
        Forms.update_form(
          target.id,
          %{
            "fields" => [
              %{"id" => t_name.id, "label" => "Name"},
              %{
                "id" => t_service.id,
                "label" => "Service",
                "option_rows_present" => "1",
                "option_rows" => %{
                  "0" => %{"value" => "web", "label" => "Website"},
                  "1" => %{"value" => "brand", "label" => "Brand identity"}
                }
              }
            ]
          },
          user
        )

      Translations.target_saved(Form, target.id)

      source = load(source.id)
      [s_name, s_service] = source.fields

      {:ok, _} =
        Forms.update_form(
          source.id,
          %{
            "fields" => [
              %{"id" => s_name.id, "required" => "false", "label" => "Fullt navn"},
              %{
                "id" => s_service.id,
                "option_rows_present" => "1",
                "option_rows" => %{
                  "0" => %{"value" => "web", "label" => "Nettside"},
                  "1" => %{"value" => "brand", "label" => "Merkevare"},
                  "2" => %{"value" => "campaign", "label" => "Kampanje"}
                }
              }
            ]
          },
          user
        )

      Translations.source_saved(load(source.id))

      payload = Translations.decode_payload(Translations.get_pending_version(Form, target.id))
      [p_name, p_service] = payload.fields

      assert p_name.required == false
      assert p_name.label == "Name"
      assert p_service.label == "Service"
      assert p_service.option_values == ["web", "brand", "campaign"]
      assert p_service.option_labels == %{"web" => "Website", "brand" => "Brand identity"}
      # Until it is translated, the new option shows its value
      assert Field.options(p_service) == [
               {"web", "Website"},
               {"brand", "Brand identity"},
               {"campaign", "campaign"}
             ]
    end
  end
end

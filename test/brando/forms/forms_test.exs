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

  # No form has id 0.
  defp submission(key, scope \\ "public", form_id \\ 0) do
    Brando.Repo.insert!(%Brando.Forms.Submission{
      scope: scope,
      form_id: form_id,
      form_key: key,
      language: "en",
      data: %{"a" => "b"}
    })
  end

  def send_query(_event, _measurements, metadata, test_pid) do
    if self() == test_pid, do: send(test_pid, {:query, metadata.query})
  end

  defp queries_of(fun) do
    handler = "forms-purge-#{System.unique_integer([:positive])}"
    event = Brando.Repo.repo().config()[:telemetry_prefix] ++ [:query]
    :ok = :telemetry.attach(handler, event, &__MODULE__.send_query/4, self())

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    collect_queries([])
  end

  defp collect_queries(queries) do
    receive do
      {:query, query} -> collect_queries([query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end

  # Audit F51: nothing read or purged a deleted form's submissions but its key
  describe "deleting a form" do
    test "deleting the last language of a key deletes its submissions in this scope", %{user: user} do
      {:ok, form} = create_form(user, %{"key" => "gone"})
      submission("gone", "public", form.id)
      submission("gone")
      elsewhere = submission("gone", "tenant_other_production")
      other_key = submission("kept")

      assert {:ok, _} = Forms.delete_form(form.id, user)

      assert Forms.count_submissions("gone") == 0
      assert Brando.Repo.get(Brando.Forms.Submission, elsewhere.id)
      assert Brando.Repo.get(Brando.Forms.Submission, other_key.id)

      assert {:ok, _} = create_form(user, %{"key" => "gone"})
      assert Forms.stream_submissions("gone") == []
    end

    test "deleting one language of several keeps the submissions", %{user: user} do
      {:ok, english} = create_form(user, %{"key" => "shared", "language" => "en"})
      {:ok, norwegian} = create_form(user, %{"key" => "shared", "language" => "no"})
      submission("shared")

      assert {:ok, _} = Forms.delete_form(english.id, user)
      assert Forms.count_submissions("shared") == 1

      assert {:ok, _} = Forms.delete_form(norwegian.id, user)
      assert Forms.count_submissions("shared") == 0
    end

    test "the delete dialog says what goes, for the last language only", %{user: user} do
      alias BrandoAdmin.LiveView.Listing.DeleteDescription

      {:ok, english} = create_form(user, %{"key" => "asked", "language" => "en"})
      assert {:ok, %{html: html}} = {:ok, DeleteDescription.describe(Form, english)}
      refute html =~ "submission"

      submission("asked")
      submission("asked")
      assert DeleteDescription.describe(Form, english).html =~ "2 submissions"

      {:ok, _norwegian} = create_form(user, %{"key" => "asked", "language" => "no"})
      refute DeleteDescription.describe(Form, english).html =~ "submission"
    end

    test "the delete dialog does not count what a renamed form keeps", %{user: user} do
      alias BrandoAdmin.LiveView.Listing.DeleteDescription

      {:ok, renamed} = create_form(user, %{"key" => "asked"})
      submission("asked", "public", renamed.id)
      {:ok, _} = Forms.update_form(renamed.id, %{"key" => "asked-now"}, user)
      {:ok, reused} = create_form(user, %{"key" => "asked"})

      refute DeleteDescription.describe(Form, reused).html =~ "submission"

      submission("asked", "public", reused.id)
      assert DeleteDescription.describe(Form, reused).html =~ "submission"
      refute DeleteDescription.describe(Form, reused).html =~ "2 submissions"
    end
  end

  # A purge deletes personal data for good. Whatever asks for it, it stops at a
  # key a form in that scope holds.
  describe "purging the submissions of deleted forms" do
    alias Brando.Worker.OrphanedRowsPurge

    test "never reaches a live form's submissions", %{user: user} do
      {:ok, _live} = create_form(user, %{"key" => "live"})
      live_row = submission("live")
      orphan = submission("orphan")

      assert Forms.purge_submissions_of_deleted_form("live") == 0

      assert :ok =
               OrphanedRowsPurge.perform(%Oban.Job{args: %{"form_keys" => ["live", "orphan"], "tenant_prefix" => nil}})

      assert Brando.Repo.get(Brando.Forms.Submission, live_row.id)
      refute Brando.Repo.get(Brando.Forms.Submission, orphan.id)
    end

    test "the report names keys without a form and deletes nothing", %{user: user} do
      {:ok, _live} = create_form(user, %{"key" => "live"})
      submission("live")
      orphan = submission("orphan")
      submission("orphan")
      submission("other-scope", "tenant_other_production")

      assert %{environments: %{}, forms: [%{scope: "public", key: "orphan", count: 2}]} = OrphanedRowsPurge.report()
      assert Brando.Repo.get(Brando.Forms.Submission, orphan.id)
    end

    test "the operator's purge locks the forms table first, deleting a form does not", %{user: user} do
      submission("orphan")
      queries = queries_of(fn -> assert Forms.purge_orphaned_submissions(["orphan"]) == 1 end)

      lock = Enum.find_index(queries, &(&1 =~ ~s(LOCK TABLE "public".forms IN SHARE MODE)))
      delete = Enum.find_index(queries, &(&1 =~ ~s(DELETE FROM "public"."forms_submissions")))
      assert lock && delete && lock < delete

      {:ok, form} = create_form(user, %{"key" => "gone"})
      refute Enum.any?(queries_of(fn -> Forms.delete_form(form.id, user) end), &(&1 =~ "LOCK TABLE"))
    end

    # The key can be edited, and its rows keep the old one
    test "a renamed form's rows are neither reported nor purged under the old key", %{user: user} do
      {:ok, form} = create_form(user, %{"key" => "contact"})
      old = submission("contact", "public", form.id)
      {:ok, _} = Forms.update_form(form.id, %{"key" => "contact-us"}, user)

      assert OrphanedRowsPurge.report().forms == []
      assert Forms.submissions_without_form() == []
      assert Forms.purge_orphaned_submissions(["contact"]) == 0
      assert Forms.purge_submissions_of_deleted_form("contact") == 0

      assert :ok = OrphanedRowsPurge.perform(%Oban.Job{args: %{"form_keys" => ["contact"], "tenant_prefix" => nil}})
      assert Brando.Repo.get(Brando.Forms.Submission, old.id)
    end

    test "deleting a new form with a renamed form's old key leaves the renamed form's rows", %{user: user} do
      {:ok, form} = create_form(user, %{"key" => "contact"})
      old = submission("contact", "public", form.id)
      {:ok, _} = Forms.update_form(form.id, %{"key" => "contact-us"}, user)

      {:ok, new} = create_form(user, %{"key" => "contact"})
      newer = submission("contact", "public", new.id)
      assert {:ok, _} = Forms.delete_form(new.id, user)

      assert Brando.Repo.get(Brando.Forms.Submission, old.id)
      refute Brando.Repo.get(Brando.Forms.Submission, newer.id)
    end

    test "nothing is purged without naming a key", %{user: user} do
      {:ok, _} = create_form(user, %{"key" => "live"})
      orphan = submission("orphan")

      assert :ok = OrphanedRowsPurge.perform(%Oban.Job{args: %{"form_keys" => [], "tenant_prefix" => nil}})
      assert Brando.Repo.get(Brando.Forms.Submission, orphan.id)
    end

    test "a job naming an environment without tenancy is cancelled, whatever the forms table holds" do
      orphan = submission("orphan")
      args = %{"form_keys" => ["orphan"], "tenant_prefix" => "public"}

      assert {:cancel, _reason} = OrphanedRowsPurge.perform(%Oban.Job{args: args})
      assert Brando.Repo.get(Brando.Forms.Submission, orphan.id)
    end

    test "without tenancy there is no environment operation to wait for" do
      submission("orphan")
      args = %{"form_keys" => ["orphan"], "tenant_prefix" => nil}

      queries = queries_of(fn -> assert :ok = OrphanedRowsPurge.perform(%Oban.Job{args: args}) end)
      refute Enum.any?(queries, &(&1 =~ "pg_advisory_lock"))
    end
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

defmodule Brando.Forms.MessagesTest do
  use Brando.ConnCase, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Factory
  alias Brando.Forms
  alias Brando.Forms.Messages
  alias Brando.Forms.Validation

  setup do
    user = Factory.insert(:random_user)

    {:ok, _} =
      Forms.create_form(
        %{
          "title" => "Contact",
          "key" => "contact",
          "language" => "en",
          "status" => "published",
          "fields" => [%{"key" => "name", "type" => "text", "label" => "Name", "required" => "true"}]
        },
        user
      )

    # A language Brando has no translation for, as a site could have
    %{user: user, form: %{Forms.get_published_form("contact", "en") | language: "de"}}
  end

  test "without the site's wording, Brando's is used: translated where it has a translation" do
    assert Forms.message(:required, "en") == Messages.built_in(:required, "en")
    assert Forms.message(:required, "no") == Messages.built_in(:required, "no")
    refute Forms.message(:required, "no") == Forms.message(:required, "en")
    assert Forms.message(:required, "de") == Forms.message(:required, "en")
  end

  test "a new set is worded in the languages Brando translates, leaving the others to write", %{user: user} do
    assert {:ok, messages} = Forms.ensure_messages(user)
    assert messages.required["no"] == Messages.built_in(:required, "no")
    assert messages.required["en"] == Messages.built_in(:required, "en")
    assert Messages.prefilled(["de", "no"]).required == %{"no" => Messages.built_in(:required, "no")}
    assert {:ok, %{id: id}} = Forms.ensure_messages(user)
    assert id == messages.id
  end

  test "the site's wording comes first, language by language", %{user: user, form: form} do
    {:ok, messages} = Forms.ensure_messages(user)
    assert Forms.message(:required, "de") == Messages.built_in(:required, "de")

    {:ok, _} =
      Forms.update_messages(
        messages.id,
        %{
          "required" => %{"de" => "Bitte ausfüllen.", "no" => ""},
          "submit_label" => %{"de" => "Absenden"},
          "failure_message" => %{"de" => "Nicht gesendet."}
        },
        user
      )

    assert Forms.message(:required, "de") == "Bitte ausfüllen."
    assert Forms.message(:required, "no") == Messages.built_in(:required, "no")
    assert {:error, %{"name" => ["Bitte ausfüllen."]}} = Validation.validate(form, %{})

    html = render_component(&Brando.HTML.Forms.site_form/1, form: form, csrf_token: false)
    assert html =~ ~r/<button[^>]*>\s*Absenden\s*<\/button>/
    assert html =~ "Nicht gesendet."
  end

  test "a form's own submit label and success message come before the site's", %{user: user, form: form} do
    {:ok, messages} = Forms.ensure_messages(user)
    {:ok, _} = Forms.update_messages(messages.id, %{"success_message" => %{"de" => "Danke."}}, user)

    assert Forms.success_message(form) == "Danke."
    assert Forms.success_message(%{form | success_message: "Vielen Dank!"}) == "Vielen Dank!"
  end
end

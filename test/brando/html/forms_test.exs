defmodule Brando.HTML.FormsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Brando.Forms.Field
  alias Brando.Forms.Form
  alias Brando.HTML.Forms

  # The wording around a form is the site's (`Brando.Forms.Messages`), read from the database
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(BrandoIntegration.Repo)
  end

  defp form do
    %Form{
      key: "contact",
      language: :en,
      intro: "We reply within a day.",
      fields: [
        %Field{key: "name", type: :text, label: "Name", required: true, width: :half},
        %Field{key: "email", type: :email, label: "Email", width: :half, help_text: "Never shared."},
        %Field{key: "project", type: :section, label: "Your project", help_text: "Tell us more"},
        %Field{
          key: "service",
          type: :radio,
          label: "Service",
          new_row: true,
          option_values: ["web", "brand"],
          option_labels: %{"web" => "Website"}
        },
        %Field{key: "topics", type: :checkboxes, label: "Topics", option_values: ["a", "b"], option_labels: %{}},
        %Field{key: "source", type: :hidden, default_value: "landing"}
      ]
    }
  end

  defp doc(html), do: Floki.parse_document!(html)

  test "renders sections, fields and hidden inputs with their posted names" do
    assigns = %{form: form()}
    html = rendered_to_string(~H(<Forms.site_form form={@form} action="/submit" />))
    doc = doc(html)

    assert [{"form", _, _}] = Floki.find(doc, "form#form-contact[action='/submit'][method='post']")
    assert Floki.text(Floki.find(doc, ".site-form-intro")) =~ "We reply within a day."
    # Fields before the first section form a group of their own
    assert [first, second] = Floki.find(doc, "fieldset.site-form-section")
    assert Floki.find(first, "legend") == []
    assert Floki.text(Floki.find(second, "legend")) =~ "Your project"

    assert [_] = Floki.find(doc, "input[name='fields[name]'][required]")
    assert [_] = Floki.find(doc, "input[type='email'][name='fields[email]'][aria-describedby='form-contact-email-help']")
    assert [_, _] = Floki.find(doc, "input[type='radio'][name='fields[service]']")
    assert [_, _] = Floki.find(doc, "input[type='checkbox'][name='fields[topics][]']")
    assert [_] = Floki.find(doc, "input[type='hidden'][name='fields[source]'][value='landing']")

    # A missing option label falls back to its value
    assert Floki.text(Floki.find(doc, ".site-form-field[data-key='service'] .site-form-choice")) =~ "brand"
    assert [_] = Floki.find(doc, ".site-form-field[data-key='name'][data-width='half']")
    assert [_] = Floki.find(doc, ".site-form-field[data-key='service'][data-new-row]")
    assert Floki.text(Floki.find(doc, "button[type='submit']")) =~ "Send"
  end

  test "a field slot replaces one field and can wrap the default markup" do
    assigns = %{form: form()}

    html =
      rendered_to_string(~H"""
      <Forms.site_form form={@form} except={["topics"]}>
        <:field :let={f} key="email">
          <div class="wrapped"><Forms.default_field {f} /></div>
        </:field>
        <:field :let={f} type="radio">
          <p class="custom-radio">{f.name}</p>
        </:field>
        <:submit>Go</:submit>
      </Forms.site_form>
      """)

    doc = doc(html)
    assert [_] = Floki.find(doc, ".wrapped .site-form-field input[name='fields[email]']")
    assert Floki.text(Floki.find(doc, ".custom-radio")) == "fields[service]"
    assert Floki.find(doc, "input[name='fields[topics][]']") == []
    assert Floki.text(Floki.find(doc, "button[type='submit']")) =~ "Go"
  end

  test "values and errors fill the form in again" do
    assigns = %{form: form()}

    html =
      rendered_to_string(~H"""
      <Forms.site_form form={@form} values={%{"name" => "Ada", "service" => "web"}} errors={%{"name" => ["can't be blank"]}} />
      """)

    doc = doc(html)
    assert [_] = Floki.find(doc, "input[name='fields[name]'][value='Ada'][aria-invalid='true']")
    assert Floki.text(Floki.find(doc, "#form-contact-name-error")) =~ "can't be blank"
    assert [_] = Floki.find(doc, "input[name='fields[service]'][value='web'][checked]")
  end

  test "a preview renders a disabled div, since it sits inside another form" do
    assigns = %{form: form()}
    doc = doc(rendered_to_string(~H(<Forms.site_form form={@form} action="/submit" preview />)))

    assert Floki.find(doc, "form") == []
    assert [{"div", attrs, _}] = Floki.find(doc, "div.site-form")
    refute List.keymember?(attrs, "action", 0)
    assert [_, _] = Floki.find(doc, "fieldset[disabled]")
  end
end

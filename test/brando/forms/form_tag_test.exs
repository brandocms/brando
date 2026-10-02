defmodule Brando.Forms.FormTagTest do
  use Brando.ConnCase, async: false

  alias Brando.Factory
  alias Brando.Forms
  alias Brando.Forms.Delivery
  alias Brando.Forms.Form
  alias Brando.Translations

  setup do
    user = Factory.insert(:random_user)

    {:ok, english} =
      Forms.create_form(
        %{
          "title" => "Contact",
          "key" => "contact",
          "language" => "en",
          "status" => "published",
          "fields" => [%{"key" => "email", "type" => "email", "label" => "Email"}]
        },
        user
      )

    {:ok, norwegian} = Translations.create_target(Form, english.id, :no, user)
    [field] = Forms.list_forms_by_key("contact") |> Enum.find(&(&1.id == norwegian.id)) |> Map.fetch!(:fields)

    {:ok, _} =
      Forms.update_form(
        norwegian.id,
        %{"status" => "published", "fields" => [%{"id" => field.id, "label" => "E-post"}]},
        user
      )

    %{user: user, english: english, norwegian: norwegian}
  end

  defp render(template, assigns) do
    Brando.Villain.parse_and_render(template, Liquex.Context.new(assigns))
  end

  test "a form key renders the published form in the entry's language" do
    html = render("{% form 'contact' %}", %{"language" => "no"})

    assert html =~ ~s(<form id="form-contact")
    assert html =~ ~s(action="/__brando/forms/contact")
    assert html =~ "E-post"
    assert html =~ ~s(name="_language" value="no")
    # Stored with the block, so the token is filled in per request
    assert html =~ ~s(<input type="hidden" name="_csrf_token" value="$csrftoken">)

    assert render("{% form 'contact' %}", %{"language" => "en"}) =~ ">\n  Email"
  end

  test "args set the class and id" do
    html = render("{% form 'contact' { class: 'wide', id: 'contact-us' } %}", %{"language" => "en"})
    assert html =~ ~s(<form id="contact-us")
    assert html =~ ~s(class="site-form wide")
  end

  test "the admin renders a preview that cannot be submitted" do
    html = render("{% form 'contact' %}", %{"language" => "en", "brando_render_for_admin" => true})

    assert html =~ ~s(<div id="form-contact")
    refute html =~ "<form"
    refute html =~ "_csrf_token"
  end

  test "a form that is not published in the language renders a comment", %{user: user, norwegian: norwegian} do
    {:ok, _} = Forms.update_form(norwegian.id, %{"status" => "draft"}, user)

    assert render("{% form 'contact' %}", %{"language" => "no"}) =~ "<!-- form \"contact\" is not published in no -->"
  end

  test "a form var shows the form in the page's language", %{user: user, english: english} do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          code: "{% form contact %}",
          name: "Form",
          namespace: "all",
          help_text: "Help",
          vars: [%{key: "contact", label: "Contact", type: "form"}]
        }),
        user
      )

    block = %{
      block: %{
        type: :module,
        source: "Elixir.Brando.Pages.Page.Blocks",
        module_id: module.id,
        uid: Brando.Utils.generate_uid(),
        refs: [],
        vars: [%{key: "contact", label: "Contact", type: :form, form_id: english.id}]
      }
    }

    html = Brando.Villain.parse([block], %Brando.Pages.Page{language: :no})
    assert html =~ "E-post"
  end

  test "finalize fills in the visitor's token on a dynamic site" do
    html = render("{% form 'contact' %}", %{"language" => "en"})
    finalized = Delivery.finalize(html)

    refute finalized =~ "$csrftoken"
    assert finalized =~ ~s(name="_csrf_token" value="#{Plug.CSRFProtection.get_csrf_token()}")
    assert Delivery.finalize("<p>No form</p>") == "<p>No form</p>"
  end

  test "a HEEx module renders the form with its slots", %{user: user} do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          type: :heex,
          code: ~s(<.site_form form="contact"><:submit>Go</:submit></.site_form>),
          name: "Form",
          namespace: "all",
          help_text: "Help"
        }),
        user
      )

    block = %{
      block: %{
        type: :module,
        source: "Elixir.Brando.Pages.Page.Blocks",
        module_id: module.id,
        uid: Brando.Utils.generate_uid(),
        refs: [],
        vars: []
      }
    }

    html = Brando.Villain.parse([block], %Brando.Pages.Page{language: :no})
    assert html =~ "E-post"
    assert html =~ ~r/<button[^>]*>\s*Go\s*<\/button>/
    assert html =~ "$csrftoken"
  end

  test "saving a form re-renders the pages that hold it", %{user: user, english: english} do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          code: "{% form contact %}",
          name: "Form",
          namespace: "all",
          help_text: "Help",
          vars: [%{key: "contact", label: "Contact", type: "form"}]
        }),
        user
      )

    page =
      Brando.Repo.insert!(%Brando.Pages.Page{
        title: "Contact",
        uri: "contact",
        language: :en,
        status: :published,
        template: "default.html",
        creator_id: user.id
      })

    params = %{
      "uid" => Brando.Utils.generate_uid(),
      "type" => "module",
      "module_id" => module.id,
      "creator_id" => user.id,
      "source" => to_string(Brando.Pages.Page.Blocks),
      "vars" => [%{"key" => "contact", "label" => %{"en" => "Contact"}, "type" => "form", "form_id" => english.id}]
    }

    block =
      %Brando.Content.Block{} |> Brando.Content.Block.recursive_block_changeset(params, user) |> Brando.Repo.insert!()

    Brando.Repo.insert!(struct(Brando.Pages.Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: 0}))
    Brando.Content.Blocks.render_entry(Brando.Pages.Page, page.id)
    assert Brando.Repo.get!(Brando.Pages.Page, page.id).rendered_blocks =~ "Email"

    [field] = Forms.get_published_form("contact", "en").fields
    {:ok, _} = Forms.update_form(english.id, %{"fields" => [%{"id" => field.id, "label" => "Your email"}]}, user)

    assert Brando.Repo.get!(Brando.Pages.Page, page.id).rendered_blocks =~ "Your email"
  end
end

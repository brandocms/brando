defmodule BrandoAdmin.Live.BlockFormVarTest do
  # A block with a form var opens in the page editor, its select offering the
  # forms there are.
  use Brando.LiveCase

  alias Brando.Content.Block
  alias Brando.Content.Var
  alias Brando.Factory

  test "a block with a form var mounts with the form selected", %{conn: conn, current_user: user} do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          code: "{{ contact }}",
          vars: [%{key: "contact", label: "Contact form", type: :form, placement: :content}]
        }),
        user
      )

    {:ok, form} =
      Brando.Forms.create_form(
        %{
          "title" => "Contact us",
          "key" => "contact-us",
          "language" => "en",
          "status" => "published",
          "fields" => [%{"key" => "name", "type" => "text", "label" => "Name"}]
        },
        user
      )

    block = %Block{
      type: :module,
      active: true,
      source: Brando.Pages.Page.Blocks,
      module_id: module.id,
      uid: Brando.Utils.generate_uid(),
      creator_id: user.id,
      vars: [
        %Var{
          key: "contact",
          label: %{"en" => "Contact form"},
          type: :form,
          placement: :content,
          form_id: form.id,
          creator_id: user.id
        }
      ]
    }

    page =
      Factory.insert(:page, creator: user, entry_blocks: [%Brando.Pages.Page.Blocks{sequence: 0, block: block}])

    {:ok, view, _html} = live(conn, "/admin/pages/update/#{page.id}")
    render_async(view)

    assert view |> element(".variable.form .select-label") |> render() =~ "Contact us"
  end
end

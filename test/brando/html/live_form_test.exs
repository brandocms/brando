defmodule Brando.HTML.Forms.LiveFormTest.FormLive do
  @moduledoc false
  use Phoenix.LiveView

  def mount(_params, %{"key" => key}, socket) do
    {:ok,
     socket
     |> assign(:form, Brando.Forms.get_published_form(key, "en"))
     |> assign(:meta, Map.put(Brando.HTML.Forms.LiveForm.connect_meta(socket), :url, "https://example.com/live"))}
  end

  def render(assigns) do
    ~H"""
    <.live_component module={Brando.HTML.Forms.LiveForm} id="contact" form={@form} meta={@meta}>
      <:submit>Send it</:submit>
      <:success>
        <p>Got it.</p>
      </:success>
    </.live_component>
    """
  end
end

defmodule Brando.HTML.Forms.LiveFormTest do
  use Brando.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Brando.Factory
  alias Brando.Forms
  alias Brando.HTML.Forms.LiveFormTest.FormLive

  setup do
    Brando.Forms.RateLimit.reset()
    user = Factory.insert(:random_user)

    {:ok, form} =
      Forms.create_form(
        %{
          "title" => "Contact",
          "key" => "contact",
          "language" => "en",
          "status" => "published",
          "fields" => [
            %{"key" => "name", "type" => "text", "label" => "Name", "required" => "true"},
            %{"key" => "email", "type" => "email", "label" => "Email", "required" => "true"}
          ]
        },
        user
      )

    %{form: form, user: user}
  end

  defp mount_form(conn), do: live_isolated(conn, FormLive, session: %{"key" => "contact"})

  test "renders the form with its slots, without the script or a token", %{conn: conn} do
    {:ok, view, html} = mount_form(conn)

    assert html =~ "Send it"
    refute html =~ "__brandoSiteForms"
    refute html =~ "_csrf_token"
    assert has_element?(view, ~s(form#contact-form[phx-submit="submit"]))
  end

  test "shows a field's errors once the visitor has been in it", %{conn: conn} do
    {:ok, view, _html} = mount_form(conn)

    # As LiveView sends it: the field not yet visited is marked unused
    html =
      view
      |> element("#contact-form")
      |> render_change(%{"fields" => %{"name" => "", "_unused_name" => "", "email" => "nope"}})

    assert html =~ "Enter a valid email address."
    refute html =~ "Fill in this field."
  end

  test "a sent form shows its success message and is stored", %{conn: conn} do
    {:ok, view, _html} = mount_form(conn)

    html =
      view |> form("#contact-form", %{"fields" => %{"name" => "Ada", "email" => "ada@example.com"}}) |> render_submit()

    assert html =~ "Got it."
    assert has_element?(view, "#contact-form.is-sent")
    assert has_element?(view, "#contact-form-sent.is-shown")
    assert [submission] = Forms.list_submissions("contact")
    assert submission.data == %{"name" => "Ada", "email" => "ada@example.com"}
    assert submission.url == "https://example.com/live"
  end

  test "a failed submission shows every field's errors", %{conn: conn} do
    {:ok, view, _html} = mount_form(conn)

    html = view |> form("#contact-form", %{"fields" => %{"name" => "", "email" => ""}}) |> render_submit()

    assert html =~ "Fill in this field."
    assert Forms.count_submissions("contact") == 0
  end

  test "a form with a page to go to sends the visitor there", %{conn: conn, form: form, user: user} do
    {:ok, _} = Forms.update_form(form.id, %{"redirect_url" => "/thank-you"}, user)
    {:ok, view, _html} = mount_form(conn)

    assert {:error, {:redirect, %{to: "/thank-you"}}} =
             view
             |> form("#contact-form", %{"fields" => %{"name" => "Ada", "email" => "ada@example.com"}})
             |> render_submit()
  end

  test "too many submissions show the site's message", %{conn: conn} do
    Application.put_env(:brando, Brando.Forms, rate_limit: [per_visitor: 0])
    on_exit(fn -> Application.delete_env(:brando, Brando.Forms) end)
    {:ok, view, _html} = mount_form(conn)

    view |> form("#contact-form", %{"fields" => %{"name" => "Ada", "email" => "ada@example.com"}}) |> render_submit()

    assert has_element?(view, "#contact-form-failed.is-shown", "Too many submissions")
  end
end

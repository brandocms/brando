defmodule Brando.HTML.Forms.LiveForm do
  @moduledoc """
  A `Brando.Forms.Form` inside a LiveView: the markup of
  `Brando.HTML.Forms.site_form/1`, with the same slots, checked as the
  visitor types and sent over the LiveView's socket.

      def mount(_params, _session, socket) do
        {:ok,
         socket
         |> assign(:contact, Brando.Forms.get_published_form("contact", "en"))
         |> assign(:form_meta, Brando.HTML.Forms.LiveForm.connect_meta(socket))}
      end

      <.live_component
        module={Brando.HTML.Forms.LiveForm}
        id="contact"
        form={@contact}
        meta={@form_meta}
      >
        <:submit>Send it</:submit>
      </.live_component>

  A field shows its errors once the visitor has been in it. A sent form shows
  its success message in place of the fields, or, when the form has a page to
  go to (`redirect_url`), sends the visitor there.

  Submissions go through `Brando.Forms.submit/3`, like a posted form: the
  same validation, honeypot, rate limit and Turnstile check, and the same
  notification. The rate limit counts visitors by IP address, which a
  component cannot read from the socket: pass `meta` from `connect_meta/1`,
  called in the LiveView's `mount/3`, and add `:url` for the page if you want
  it stored. The socket must give the `:peer_data` and `:user_agent` connect
  info:

      socket "/live", Phoenix.LiveView.Socket,
        websocket: [connect_info: [:peer_data, :user_agent, session: @session_options]]

  With Turnstile configured, load its script in your layout. The widget is
  left alone by LiveView's patches, but a token is good for one submission:
  when a check fails, the visitor is asked to reload the page.

  Attributes: `form`, `id`, `meta`, and of `site_form/1`'s, `classes`, `only`,
  `except` and `nonce`. Slots: `:intro`, `:submit`, `:success`, `:failure`,
  `:section` and `:field`.
  """
  use Phoenix.LiveComponent

  alias Brando.Forms
  alias Brando.Forms.Field
  alias Brando.Forms.Validation

  @passed [:classes, :only, :except, :nonce, :intro, :submit, :success, :failure, :section, :field]

  @doc """
  What a submission records about the visitor — their IP address and user
  agent — from the socket's connect info. Call it in the LiveView's `mount/3`.
  """
  @spec connect_meta(Phoenix.LiveView.Socket.t()) :: map()
  def connect_meta(socket) do
    peer = connect_info(socket, :peer_data)

    %{
      ip: peer && peer[:address] && peer.address |> :inet.ntoa() |> to_string(),
      user_agent: connect_info(socket, :user_agent)
    }
  end

  defp connect_info(socket, key) do
    Phoenix.LiveView.get_connect_info(socket, key)
  rescue
    _ -> nil
  end

  @impl true
  def mount(socket) do
    {:ok, assign(socket, values: %{}, errors: %{}, sent: false, failure_message: nil)}
  end

  @impl true
  def update(assigns, socket) do
    passed = Map.take(assigns, @passed)

    {:ok,
     socket
     |> assign(:id, assigns.id)
     |> assign(:form, assigns.form)
     |> assign(:meta, Map.get(assigns, :meta, %{}))
     |> assign(:passed, passed)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :site_form,
        Map.merge(assigns.passed, %{
          form: assigns.form,
          id: "#{assigns.id}-form",
          values: assigns.values,
          errors: assigns.errors,
          sent: assigns.sent,
          failure_message: assigns.failure_message,
          enhance: false,
          csrf_token: false,
          "phx-change": "validate",
          "phx-submit": "submit",
          "phx-target": assigns.myself
        })
      )

    ~H"""
    <div id={@id} class="site-form-live">
      <Brando.HTML.Forms.site_form {@site_form} />
    </div>
    """
  end

  @impl true
  def handle_event("validate", params, socket) do
    posted = params["fields"] || %{}
    form = socket.assigns.form

    errors =
      case Validation.validate(form, posted) do
        {:ok, _data} -> %{}
        {:error, errors} -> Map.filter(errors, fn {key, _} -> used?(posted, key) end)
      end

    {:noreply, assign(socket, values: values(form, posted), errors: errors, failure_message: nil)}
  end

  def handle_event("submit", params, socket) do
    posted = params["fields"] || %{}
    socket = assign(socket, values: values(socket.assigns.form, posted), failure_message: nil)

    case Forms.submit(socket.assigns.form.key, params, socket.assigns.meta) do
      {:ok, _submission, %{redirect_url: url}} when is_binary(url) and url != "" ->
        {:noreply, redirect_to(socket, url)}

      {:ok, _submission, _form} ->
        {:noreply, assign(socket, sent: true, errors: %{})}

      {:error, {:invalid, errors}, _form} ->
        {:noreply, assign(socket, :errors, errors)}

      {:error, reason, form} when reason in [:rate_limited, :rejected] ->
        message = Forms.message(if(reason == :rejected, do: :spam_check, else: reason), form.language)
        {:noreply, assign(socket, :failure_message, message)}

      _ ->
        message = Forms.message(:failure_message, socket.assigns.form.language)
        {:noreply, assign(socket, :failure_message, message)}
    end
  end

  # What the visitor has typed, so a re-render keeps it. An unticked box sends
  # nothing, which must not bring back a ticked default.
  defp values(form, posted) do
    for %Field{key: key} = field <- form.fields, Field.input?(field), into: %{} do
      {key, Map.get(posted, key)}
    end
  end

  # LiveView marks the inputs the visitor has not been in yet.
  defp used?(posted, key), do: not Map.has_key?(posted, "_unused_" <> key)

  defp redirect_to(socket, "/" <> _ = path), do: Phoenix.LiveView.redirect(socket, to: path)
  defp redirect_to(socket, url), do: Phoenix.LiveView.redirect(socket, external: url)
end

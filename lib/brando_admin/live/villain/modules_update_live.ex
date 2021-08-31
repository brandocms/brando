defmodule BrandoAdmin.Villain.ModuleUpdateLive do
  use Surface.LiveView, layout: {BrandoAdmin.LayoutView, "live.html"}
  use BrandoAdmin.Toast
  use BrandoAdmin.Presence
  use Phoenix.HTML

  import Brando.Gettext
  import Ecto.Changeset
  import Phoenix.LiveView.Helpers
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  alias Brando.Villain
  alias Brando.Villain.Module.Ref
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.MapInputs
  alias BrandoAdmin.Components.Form.MapValueInputs
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Toast

  alias Surface.Components.Form
  alias Surface.Components.Form.Inputs

  def mount(%{"entry_id" => entry_id}, %{"user_token" => token}, socket) do
    {:ok,
     socket
     |> Surface.init()
     |> assign_entry(entry_id)
     |> assign_current_user(token)
     |> assign_changeset()
     |> set_admin_locale()
     |> assign(ref_name: nil)}
  end

  def render(assigns) do
    ~F"""
    <Content.Header
      title={gettext("Content Modules")}
      subtitle={gettext("Edit module")} />

    <Form for={@changeset} :let={form: form} change="validate" submit="save">
      <div class="block-editor">
        <div class="code">
          <Input.Code form={form} field={:code} />
        </div>
        <div class="properties shaded">
          <div class="inner">
            <Input.Text form={form} field={:name} />
            <Input.Text form={form} field={:namespace} />
            <Input.Textarea form={form} field={:help_text} />
            <Input.Text form={form} field={:class} />
            <Input.Toggle form={form} field={:multi} />

            <div class="button-group">
              <button :on-click="show_modal" phx-value-id={"#{form.id}-wrapper"} class="secondary" type="button">Edit wrapper</button>
              <button :on-click="show_modal" phx-value-id={"#{form.id}-icon"} class="secondary" type="button">Edit icon</button>
            </div>

            <Modal title="Edit wrapper" id={"#{form.id}-wrapper"}>
              <Input.Code form={form} field={:wrapper} />
            </Modal>

            <Modal title="Edit icon" id={"#{form.id}-icon"}>
              <Input.Code form={form} field={:svg} />
            </Modal>

            <div class="refs">
              <h2>
                <div class="header-spread">REFs <span class="circle small">{Enum.count(input_value(form, :refs))}</span></div>
                <button :on-click="show_modal" phx-value-id={"#{form.id}-create-ref"} type="button" class="circle">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M11 11V5h2v6h6v2h-6v6h-2v-6H5v-2z"/></svg>
                </button>
              </h2>

              <Modal title="Create ref" id={"#{form.id}-create-ref"} narrow>
                <Form
                  for={:ref_form}
                  change={"update_ref_name"}>
                  <input
                    type="text"
                    name="ref_name"
                    value={@ref_name}
                    placeholder="ref name"
                    autocomplete="off"
                  />
                </Form>

                {#if @ref_name}
                  <div class="button-group">
                    <button type="button" :on-click="create_ref" phx-value-type={"text"} phx-value-id={"#{form.id}-create-ref"} class="secondary">
                      Text
                    </button>
                    <button type="button" :on-click="create_ref" phx-value-type={"heading"} phx-value-id={"#{form.id}-create-ref"} class="secondary">
                      Heading
                    </button>
                    <button type="button" :on-click="create_ref" phx-value-type={"picture"} phx-value-id={"#{form.id}-create-ref"} class="secondary">
                      Picture
                    </button>
                  </div>
                {/if}
              </Modal>

              <ul>
                <Inputs form={form} for={:refs} :let={form: ref}>
                  <li class="padded">
                    <div>
                      {#for ref_data <- inputs_for_block(ref, :data)}
                        <span class="text-mono">{input_value(ref_data, :type)}</span>
                      {/for}
                      <span class="text-mono">- %&lcub;{input_value(ref, :name)}&rcub;</span>
                    </div>
                    <div class="actions">
                      <button class="tiny" type="button" :on-click="show_modal" phx-value-id={"#{form.id}-ref-#{input_value(ref, :name)}"}>
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M6.414 16L16.556 5.858l-1.414-1.414L5 14.586V16h1.414zm.829 2H3v-4.243L14.435 2.322a1 1 0 0 1 1.414 0l2.829 2.829a1 1 0 0 1 0 1.414L7.243 18zM3 20h18v2H3v-2z"/></svg>
                      </button>
                      <button class="tiny" type="button">
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M17 6h5v2h-2v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V8H2V6h5V3a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v3zm1 2H6v12h12V8zm-4.586 6l1.768 1.768-1.414 1.414L12 15.414l-1.768 1.768-1.414-1.414L10.586 14l-1.768-1.768 1.414-1.414L12 12.586l1.768-1.768 1.414 1.414L13.414 14zM9 4v2h6V4H9z"/></svg>
                      </button>
                    </div>

                    <Modal title="Edit ref" id={"#{form.id}-ref-#{input_value(ref, :name)}"}>
                      <div class="panels">
                        {#for ref_data <- inputs_for_block(ref, :data)}
                          {hidden_input ref_data, :type, value: input_value(ref_data, :type)}
                          <div class="panel">
                            <h2>Block template</h2>
                            {#case input_value(ref_data, :type)}
                              {#match "header"}
                                {#for block_data <- inputs_for_block(ref_data, :data)}
                                  <Input.Text form={block_data} field={:level} />
                                  <Input.Text form={block_data} field={:text} />
                                {/for}

                              {#match "svg"}
                                {#for block_data <- inputs_for_block(ref_data, :data)}
                                  <Input.Text form={block_data} field={:class} />
                                  <Input.Code form={block_data} field={:code} />
                                {/for}

                              {#match "text"}
                                {#for block_data <- inputs_for_block(ref_data, :data)}
                                  <Input.Text form={block_data} field={:text} />
                                  <Input.Text form={block_data} field={:type} />
                                  <Input.Text form={block_data} field={:extensions} />
                                {/for}

                              {#match "picture"}
                                {#for block_data <- inputs_for_block(ref_data, :data)}
                                  {hidden_input block_data, :cdn}
                                  <Input.Text form={block_data} field={:title} />
                                  <Input.Text form={block_data} field={:alt} />
                                  <Input.Text form={block_data} field={:credits} />
                                  <Input.Text form={block_data} field={:link} />
                                  <Input.Text form={block_data} field={:picture_class} />
                                  <Input.Text form={block_data} field={:img_class} />
                                  <Input.Toggle form={block_data} field={:webp} />
                                {/for}

                              {#match "gallery"}
                                {#for block_data <- inputs_for_block(ref_data, :data)}
                                  {hidden_input block_data, :cdn}
                                  <Input.Text form={block_data} field={:class} />
                                  <Input.Text form={block_data} field={:series_slug} />
                                  <Input.Toggle form={block_data} field={:lightbox} />
                                  <Input.Radios form={block_data} field={:placeholder} options={[
                                    %{label: "Dominant color", value: "dominant_color"},
                                    %{label: "SVG", value: "svg"},
                                    %{label: "Micro", value: "micro"},
                                    %{label: "None", value: "none"}
                                  ]} />
                                {/for}

                              {#match type}
                                No matching block {type} found
                            {/case}
                          </div>

                          <div class="panel">
                            <h2>Ref config — {input_value(ref_data, :type)}</h2>

                            <Input.Text form={ref} field={:name} />
                            <Input.Text form={ref} field={:description} />
                            {hidden_input ref_data, :uid, value: input_value(ref_data, :uid) || Brando.Utils.generate_uid()}
                          </div>
                        {/for}
                      </div>
                    </Modal>
                  </li>
                </Inputs>
              </ul>
            </div>

            <div class="vars">
              <h2>
                <div class="header-spread">Vars <span class="circle small">{Enum.count(input_value(form, :vars))}</span></div>
                <button type="button" class="circle">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M11 11V5h2v6h6v2h-6v6h-2v-6H5v-2z"/></svg>
                </button>
              </h2>
              <ul>
                <Inputs form={form} for={:vars} :let={form: var}>
                  <li class="text-mono padded">
                    <Modal title="Edit var" id={"#{form.id}-var-#{input_value(var, :name)}"}>
                      <Input.Toggle form={var} field={:important} />
                      <Input.Text form={var} field={:name} />
                      <Input.Text form={var} field={:label} />
                      <Input.Radios form={var} field={:type} options={[
                        %{label: "Boolean", value: "boolean"},
                        %{label: "Text", value: "text"},
                        %{label: "String", value: "string"},
                        %{label: "Color", value: "color"}
                      ]} />
                      {#case input_value(var, :type)}
                        {#match :text}
                          <Input.Text form={var} field={:value} />

                        {#match :string}
                          <Input.Text form={var} field={:value} />

                        {#match :boolean}
                          <Input.Toggle form={var} field={:value} />

                        {#match _}
                          <Input.Text form={var} field={:value} />
                      {/case}
                    </Modal>
                    {input_value(var, :type)} - %&lcub;{input_value(var, :name)}&rcub;
                    <div class="actions">
                      <button class="tiny" type="button" :on-click="show_modal" phx-value-id={"#{form.id}-var-#{input_value(var, :name)}"}>
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M6.414 16L16.556 5.858l-1.414-1.414L5 14.586V16h1.414zm.829 2H3v-4.243L14.435 2.322a1 1 0 0 1 1.414 0l2.829 2.829a1 1 0 0 1 0 1.414L7.243 18zM3 20h18v2H3v-2z"/></svg>
                      </button>
                      <button class="tiny" type="button">
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M17 6h5v2h-2v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V8H2V6h5V3a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v3zm1 2H6v12h12V8zm-4.586 6l1.768 1.768-1.414 1.414L12 15.414l-1.768 1.768-1.414-1.414L10.586 14l-1.768-1.768 1.414-1.414L12 12.586l1.768-1.768 1.414 1.414L13.414 14zM9 4v2h6V4H9z"/></svg>
                      </button>
                    </div>
                  </li>
                </Inputs>
              </ul>

              <div class="button-group">
                <button class="primary">Save module</button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Form>

    """
  end

  def handle_params(params, url, socket) do
    uri = URI.parse(url)

    {:noreply,
     socket
     |> assign(:params, params)
     |> assign(:uri, uri)}
  end

  def handle_event("show_modal", %{"id" => modal_id}, socket) do
    Modal.show(modal_id)
    {:noreply, socket}
  end

  def handle_event("update_ref_name", %{"ref_name" => ref_name}, socket) do
    {:noreply, assign(socket, :ref_name, ref_name)}
  end

  def handle_event(
        "create_ref",
        %{"type" => block_type, "id" => modal_id},
        %{assigns: %{ref_name: ref_name, changeset: changeset}} = socket
      ) do
    refs = get_field(changeset, :refs)

    new_ref = %Ref{
      name: ref_name,
      data: %Brando.Blueprint.Villain.Blocks.HeaderBlock{
        data: %Brando.Blueprint.Villain.Blocks.HeaderBlock{}
      }
    }

    require Logger
    Logger.error(inspect(new_ref, pretty: true))

    updated_changeset = put_change(changeset, :refs, [new_ref | refs])
    Modal.hide(modal_id)

    {:noreply,
     socket
     |> assign(:changeset, updated_changeset)
     |> assign(:ref_name, nil)}
  end

  def handle_event(
        "validate",
        %{"module" => module_params},
        %{assigns: %{current_user: current_user, entry: entry}} = socket
      ) do
    changeset = Brando.Villain.Module.changeset(entry, module_params, current_user)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event(
        "save",
        %{"module" => module_params},
        %{assigns: %{current_user: user, changeset: changeset}} = socket
      ) do
    changeset = %{changeset | action: :update}

    case Villain.update_module(changeset, user) do
      {:ok, entry} ->
        Toast.send_delayed("Module updated")
        {:noreply, push_redirect(socket, to: "/admin/config/modules")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string
    |> Gettext.put_locale()

    socket
  end

  defp assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end

  defp assign_entry(socket, entry_id) do
    assign_new(socket, :entry, fn -> Brando.Villain.get_module!(entry_id) end)
  end

  defp assign_changeset(%{assigns: %{entry: entry, current_user: current_user}} = socket) do
    assign_new(socket, :changeset, fn ->
      Brando.Villain.Module.changeset(entry, %{}, current_user)
    end)
  end
end

defmodule BrandoAdmin.Components.Form.Input.Blocks.FragmentBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML
  import Brando.Gettext
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks

  # prop block, :form
  # prop base_form, :form
  # prop index, :integer
  # prop block_count, :integer
  # prop is_ref?, :boolean, default: false
  # prop belongs_to, :string
  # prop data_field, :atom

  # prop insert_module, :event, required: true
  # prop duplicate_block, :event, required: true

  # data uid, :string
  # data text_type, :string
  # data initial_props, :map
  # data block_data, :map

  def update(assigns, socket) do
    block = assigns.block
    block_data = Brando.Utils.forms_from_field(block[:data]) |> List.first()
    fragment_id = block_data[:fragment_id].value

    socket =
      cond do
        fragment_id == nil ->
          socket
          |> assign(:fragment, nil)
          |> assign(:update_url, nil)

        !socket.assigns[:fragment] && fragment_id ->
          socket
          |> assign(:fragment, get_fragment(fragment_id))
          |> assign(:update_url, get_update_url(fragment_id))

        socket.assigns[:fragment] && socket.assigns.fragment.id != fragment_id ->
          socket
          |> assign(:fragment, get_fragment(fragment_id))
          |> assign(:update_url, get_update_url(fragment_id))

        true ->
          socket
          |> assign_new(:fragment, fn -> get_fragment(fragment_id) end)
          |> assign_new(:update_url, fn -> get_update_url(fragment_id) end)
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:block_data, block_data)
     |> assign(:uid, assigns.block[:uid].value)
     |> assign_new(:fragment_options, fn ->
       available_fragments = get_available_fragments()

       Enum.map(available_fragments, fn fragment ->
         %{
           label: "[#{fragment.parent_key}] #{fragment.title} — #{fragment.language}",
           value: fragment.id
         }
       end)
     end)}
  end

  defp get_fragment(fragment_id) do
    case Brando.Pages.get_fragment(fragment_id) do
      {:ok, fragment} -> fragment
      _ -> nil
    end
  end

  defp get_update_url(fragment_id) do
    update_view = BrandoAdmin.Pages.PageFragmentUpdateLive

    Brando.routes().admin_live_path(
      Brando.endpoint(),
      update_view,
      fragment_id
    )
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>
      <Blocks.block
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}>
        <:description>
          <%= if @fragment do %>
            [<%= @fragment.parent_key %>] <%= @fragment.title %> — <%= @fragment.language %>
          <% end %>
        </:description>
        <:config>
          <.live_component module={Input.Select}
            id={"#{@block_data.id}-fragment-select"}
            field={@block_data[:fragment_id]}
            label={gettext "Fragment"}
            opts={[options: @fragment_options]}
            in_block
          />
        </:config>
        <div class="fragment-block" id={"block-#{@uid}-svg-drop"} data-target={@myself}>
          <%= if @fragment do %>
            <div class="empty">
              <figure>
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M14.25 6.087c0-.355.186-.676.401-.959.221-.29.349-.634.349-1.003 0-1.036-1.007-1.875-2.25-1.875s-2.25.84-2.25 1.875c0 .369.128.713.349 1.003.215.283.401.604.401.959v0a.64.64 0 01-.657.643 48.39 48.39 0 01-4.163-.3c.186 1.613.293 3.25.315 4.907a.656.656 0 01-.658.663v0c-.355 0-.676-.186-.959-.401a1.647 1.647 0 00-1.003-.349c-1.036 0-1.875 1.007-1.875 2.25s.84 2.25 1.875 2.25c.369 0 .713-.128 1.003-.349.283-.215.604-.401.959-.401v0c.31 0 .555.26.532.57a48.039 48.039 0 01-.642 5.056c1.518.19 3.058.309 4.616.354a.64.64 0 00.657-.643v0c0-.355-.186-.676-.401-.959a1.647 1.647 0 01-.349-1.003c0-1.035 1.008-1.875 2.25-1.875 1.243 0 2.25.84 2.25 1.875 0 .369-.128.713-.349 1.003-.215.283-.4.604-.4.959v0c0 .333.277.599.61.58a48.1 48.1 0 005.427-.63 48.05 48.05 0 00.582-4.717.532.532 0 00-.533-.57v0c-.355 0-.676.186-.959.401-.29.221-.634.349-1.003.349-1.035 0-1.875-1.007-1.875-2.25s.84-2.25 1.875-2.25c.37 0 .713.128 1.003.349.283.215.604.401.96.401v0a.656.656 0 00.658-.663 48.422 48.422 0 00-.37-5.36c-1.886.342-3.81.574-5.766.689a.578.578 0 01-.61-.58v0z" />
                </svg>
              </figure>
              <div class="instructions">
                <div class="embedded-fragment">
                  <%= gettext "Embedded fragment" %>: <br>
                  <div class="fragment-path">
                    [<%= @fragment.parent_key %>] <%= @fragment.title %> — <%= @fragment.language %>
                  </div>
                </div>
                <%= if @update_url do %>
                  <.link href={@update_url} class="tiny" target="_blank">
                    <%= gettext "Edit fragment" %>
                  </.link>
                <% end %>
              </div>
            </div>
          <% else %>
            <div class="empty">
              <figure>
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M14.25 6.087c0-.355.186-.676.401-.959.221-.29.349-.634.349-1.003 0-1.036-1.007-1.875-2.25-1.875s-2.25.84-2.25 1.875c0 .369.128.713.349 1.003.215.283.401.604.401.959v0a.64.64 0 01-.657.643 48.39 48.39 0 01-4.163-.3c.186 1.613.293 3.25.315 4.907a.656.656 0 01-.658.663v0c-.355 0-.676-.186-.959-.401a1.647 1.647 0 00-1.003-.349c-1.036 0-1.875 1.007-1.875 2.25s.84 2.25 1.875 2.25c.369 0 .713-.128 1.003-.349.283-.215.604-.401.959-.401v0c.31 0 .555.26.532.57a48.039 48.039 0 01-.642 5.056c1.518.19 3.058.309 4.616.354a.64.64 0 00.657-.643v0c0-.355-.186-.676-.401-.959a1.647 1.647 0 01-.349-1.003c0-1.035 1.008-1.875 2.25-1.875 1.243 0 2.25.84 2.25 1.875 0 .369-.128.713-.349 1.003-.215.283-.4.604-.4.959v0c0 .333.277.599.61.58a48.1 48.1 0 005.427-.63 48.05 48.05 0 00.582-4.717.532.532 0 00-.533-.57v0c-.355 0-.676.186-.959.401-.29.221-.634.349-1.003.349-1.035 0-1.875-1.007-1.875-2.25s.84-2.25 1.875-2.25c.37 0 .713.128 1.003.349.283.215.604.401.96.401v0a.656.656 0 00.658-.663 48.422 48.422 0 00-.37-5.36c-1.886.342-3.81.574-5.766.689a.578.578 0 01-.61-.58v0z" />
                </svg>
              </figure>
              <div class="instructions">
                <button type="button" class="tiny" phx-click={show_modal("#block-#{@uid}_config")}><%= gettext "Configure fragment block" %></button>
              </div>
            </div>
          <% end %>
        </div>
      </Blocks.block>
    </div>
    """
  end

  defp get_available_fragments do
    Brando.Pages.list_fragments!(%{
      order: "asc parent_key, asc key, desc inserted_at",
      cache: {:ttl, :infinite}
    })
  end
end

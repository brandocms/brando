defmodule BrandoAdmin.Components.Content.List.Row do
  use Surface.LiveComponent
  import Brando.Gettext

  alias Brando.Trait.SoftDelete
  alias BrandoAdmin.Components.Content.List.Row

  prop entry, :any
  prop selected_rows, :list
  prop listing, :any
  prop schema, :any
  prop sortable?, :boolean
  prop status?, :boolean
  prop creator?, :boolean
  prop click, :event, required: true
  prop target, :any, required: true

  data soft_delete?, :boolean
  data show_children, :boolean
  data child_fields, :list

  def mount(socket) do
    {:ok, assign(socket, show_children: false, child_fields: [])}
  end

  def update(%{show_children: show_children, child_fields: child_fields}, socket) do
    {:ok, assign(socket, show_children: show_children, child_fields: child_fields)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:singular, assigns.schema.__naming__.singular)
     |> assign(:soft_delete?, assigns.schema.has_trait(SoftDelete))}
  end

  def render(assigns) do
    ~F"""
    <div
      class={"list-row", "draggable", selected: @entry.id in @selected_rows}
      data-id={@entry.id}
      :on-click={@click}
      phx-value-id={@entry.id}
      phx-page-loading>
      <div class="main-content">
        {#if @sortable?}
          <Row.Handle />
        {/if}

        {#if @status?}
          <Row.Status
            entry={@entry}
            soft_delete?={@soft_delete?} />
        {/if}

        {#for field <- @listing.fields}
          <Row.Field
            field={field}
            entry={@entry}
            schema={@schema} />
        {/for}

        {#if @creator?}
          <Row.Creator
            entry={@entry}
            soft_delete?={@soft_delete?}/>
        {/if}

        <Row.EntryMenu
          entry={@entry}
          listing={@listing} />
      </div>
      {#if @show_children}
        {#for child_field <- @child_fields}
          {#for child_entry <- Map.get(@entry, child_field)}
            <Row.ChildRow
              entry={child_entry}
              schema={@schema}
              child_listing={@listing.child_listing} />
          {/for}
        {/for}
        {!--

        --}
      {/if}
    </div>
    """
  end
end

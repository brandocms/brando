defmodule BrandoAdmin.Components.Content.List.Row.Field do
  use Surface.Component

  alias Brando.Blueprint.Listings.Template
  alias BrandoAdmin.Components.CircleFlag
  alias BrandoAdmin.Components.ChildrenButton

  prop entry, :any, required: true
  prop field, :any, required: true
  prop schema, :module, required: true

  data attr, :any, default: nil
  data class, :any, default: nil
  data columns, :any, default: nil
  data entry_field, :any, default: nil
  data rendered_tpl, :any, default: nil
  data offset, :any

  def update(%{field: %{__struct__: Template}} = assigns, socket) do
    class = Keyword.get(assigns.field.opts, :class)
    columns = Keyword.get(assigns.field.opts, :columns)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:class, class)
     |> assign(:columns, columns)
     |> assign_new(:rendered_tpl, fn ->
       case Map.get(assigns.field, :template) do
         nil ->
           nil

         tpl ->
           {:ok, parsed_template} = Liquex.parse(tpl, Brando.Villain.LiquexParser)

           context = Brando.Villain.get_base_context(assigns.entry)

           []
           |> Liquex.Render.render(parsed_template, context)
           |> elem(0)
           |> Enum.join()
           |> Phoenix.HTML.raw()
       end
     end)}
  end

  def update(assigns, socket) do
    attr = assigns.schema.__attribute__(assigns.field.name)
    entry_field = Map.get(assigns.entry, assigns.field.name)
    class = Keyword.get(assigns.field.opts, :class)
    columns = Keyword.get(assigns.field.opts, :columns)
    offset = Keyword.get(assigns.field.opts, :offset)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:attr, attr)
     |> assign(:entry_field, entry_field)
     |> assign(:class, class)
     |> assign(:columns, columns)
     |> assign(:offset, offset)
     |> assign(:rendered_tpl, nil)}
  end

  def render(assigns) do
    ~F"""
    {#if @rendered_tpl}
      <div class={@class, "col-#{@columns}": @columns}>
        {@rendered_tpl}
      </div>
    {#else}
      {#case @field.type}
        {#match :image}
          <div
            class={@class, "col-#{@columns}": @columns, "offset-#{@offset}": @offset}>
            {#if @entry_field}
              <img src={"/media/#{Map.get(@entry_field.sizes, "thumb")}"}>
            {#else}
              <div class="img-placeholder">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M4.828 21l-.02.02-.021-.02H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H4.828zM20 15V5H4v14L14 9l6 6zm0 2.828l-6-6L6.828 19H20v-1.172zM8 11a2 2 0 1 1 0-4 2 2 0 0 1 0 4z"/></svg>
              </div>
            {/if}
          </div>

        {#match :children_button}
          <div
            class={@class, "col-#{@columns}": @columns, "offset-#{@offset}": @offset}>
            <ChildrenButton id={"#{@entry.id}-children-button"} fields={@field.name} entry={@entry} />
          </div>

        {#match :language}
          <div
            class={@class, "col-#{@columns}": @columns, "offset-#{@offset}": @offset}>
            <CircleFlag language={@entry_field} />
          </div>
      {/case}
    {/if}
    """
  end
end

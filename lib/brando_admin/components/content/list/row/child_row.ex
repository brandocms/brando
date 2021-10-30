defmodule BrandoAdmin.Components.Content.List.Row.ChildRow do
  use Surface.Component

  alias BrandoAdmin.Components.Content.List.Row

  prop schema, :module, required: true
  prop child_listing, :any, required: true
  prop entry, :any, required: true

  data sortable?, :boolean
  data status?, :boolean
  data creator?, :boolean
  data soft_delete?, :boolean
  data listing, :map

  def render(%{schema: schema, entry: entry, child_listing: child_listing} = assigns) do
    assigns =
      assigns
      |> assign(schema: schema, entry: entry)
      |> assign(:sortable?, entry.__struct__.has_trait(Brando.Trait.Sequenced))
      |> assign(:creator?, entry.__struct__.has_trait(Brando.Trait.Creator))
      |> assign(:status?, entry.__struct__.has_trait(Brando.Trait.Status))
      |> assign(:soft_delete?, entry.__struct__.has_trait(Brando.Trait.SoftDelete))
      |> assign_new(:listing, fn ->
        entry_schema = entry.__struct__

        listing_for_schema = Keyword.fetch!(child_listing, entry_schema)
        listing = Enum.find(schema.__listings__, &(&1.name == listing_for_schema))

        if !listing do
          raise "No listing `#{inspect(listing_for_schema)}` found for `#{inspect(entry_schema)}`"
        end

        listing
      end)

    ~F"""
    <div class="child-content">
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
    """
  end
end

## Blueprints

### Identifier

### Absolute URL

### Schema

#### Attributes

#### Relations

#### Assets

### Traits

### Translations

### Listings

#### Example

```elixir
  listings do
    listing do
      query %{status: :published}
      filter label: t("Title"), filter: "title"
      action label: t("Create subpage"), event: "create_subpage"
      action label: t("Create fragment"), event: "create_fragment"
      component &__MODULE__.listing_row/1
    end
  end
```

#### Listing Query
#### Fields
##### Field types
##### Templates
#### Filters
#### Actions
#### Selection Actions
#### Child Listings

### Forms
#### Form options
#### Tabs
#### Fieldsets
#### Inputs
##### Input types
##### Inputs for (subforms)
##### Inputs for (custom components)






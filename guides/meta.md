## Meta

### Blueprint

Meta information is built from the blueprint:

    use Brando.Blueprint,
    # ...

    meta_schema do
      meta_field ["description", "og:description"], &Brando.HTML.truncate(&1, 155)
      meta_field ["title", "og:title"], [:title]
      meta_field ["title", "og:title"], &fallback(&1, [:meta_title, {:strip_tags, :title}])
      meta_field "og:image", [:meta_image]
      meta_field "og:locale", [:language], &encode_locale/1
    end

  The first argument is the key name and can also be supplied as a list of keys where
  multiple keys will share the same value.

  The second argument can point to a key in the entry's data, or a function that will 
  receive the entry as the first param.

  There are also some built in helpers you can use:

  - `fallback(data, keys)` tries `keys` until it gets a value, so in the above example it
    first tries to get `data.meta_title`, if that fails it tries `data.title`, but will strip
    it for HTML tags.

  -`encode_locale(language)` converts the locale to a format facebook/opengraph understands.

### Controller


# Test Migration Guide for Refs Refactoring

## Breaking Changes in Tests

The refactoring of refs from embedded data to their own table breaks existing tests. Here's how to fix them:

## 1. Factory Changes

### Old Way (Embedded Refs)
```elixir
module = build(:module, refs: [
  %{
    name: "TestRef",
    description: "A test ref", 
    data: %{type: "text", data: %{text: "Hello"}},
    uid: "abc123"
  }
])
```

### New Way (Has Many Refs)
```elixir
# Create module first
module = insert(:module)

# Create refs separately
ref = insert(:ref, module: module, name: "TestRef")

# Or use the factory helper
module = insert(:module_with_refs)
```

## 2. Data Structure Changes

### Old Structure
- `ref.data.data.property` - Double nested for actual data
- `ref.data.uid` - UID at data level

### New Structure  
- `ref.property` - Direct access to merged data (for pictures/videos)
- `ref.gallery.gallery_objects` - For galleries
- `ref.data.uid` - UID still at data level for polymorphic embeds

## 3. Test Assertion Updates

### Picture Refs
```elixir
# OLD
assert ref.data.data.title == "My Title"
assert ref.data.data.path == "/images/test.jpg"

# NEW  
assert ref.title == "My Title"  # Override from ref.data.data
assert ref.path == "/images/test.jpg"  # From ref.image
```

### Gallery Refs
```elixir
# OLD
assert Enum.count(ref.data.data.images) == 3

# NEW
assert Enum.count(ref.gallery.gallery_objects) == 3
```

### Video Refs
```elixir
# OLD
assert ref.data.data.url == "https://youtube.com/watch?v=123"

# NEW
assert ref.url == "https://youtube.com/watch?v=123"  # From ref.video
```

## 4. Module/Block Creation

### Old Way
```elixir
attrs = %{
  name: "Test",
  refs: [%{name: "test", data: %{type: "picture", data: %{path: "/test.jpg"}}}]
}
Content.create_module(attrs, user)
```

### New Way
```elixir
# Create module first
{:ok, module} = Content.create_module(%{name: "Test"}, user)

# Create refs separately
{:ok, ref} = Content.create_ref(%{
  name: "test",
  module_id: module.id,
  data: %{type: "picture", data: %{title: "Override"}},
  image_id: image.id
}, user)
```

## 5. Test Files That Need Updates

### High Priority (Will Break)
- `test/brando/content_test.exs` - Lines 22-29, 208-248, 268-290
- `test/brando/blueprints/villain/block/reapply_test.exs` - Lines 71-84, 270-314  
- `test/brando/villain/villain_test.exs` - Multiple refs creation patterns
- `test/brando/html_test.exs` - Lines 973-997
- `test/brando/datasource/datasources_test.exs` - Lines 29-42

### Medium Priority
- Tests that check ref structure but might work with parser compatibility

## 6. Common Patterns to Update

### Checking Ref Data
```elixir
# OLD
assert prepared_ref.data.uid != "abc123"
assert orig_header_ref.data.data.level == 1

# NEW  
assert prepared_ref.data.uid != "abc123"  # UID still in data
assert orig_header_ref.level == 1  # Direct access for merged data
```

### Creating Test Data
```elixir
# OLD - Don't do this anymore
refs: [%{name: "test", data: %{type: "picture", data: %{path: "/test.jpg"}}}]

# NEW - Use factories
refs: [build(:picture_ref, name: "test")]
```

## 7. Available Factories

- `:ref` - Basic text ref
- `:picture_ref` - Picture ref with image association
- `:video_ref` - Video ref with video association  
- `:gallery_ref` - Gallery ref with gallery association
- `:module_with_refs` - Module with sample refs
- `:gallery` - Basic gallery
- `:video` - Basic video

## 8. Preloading in Tests

Since refs are now associations, make sure to preload them:

```elixir
module = Repo.preload(module, [refs: [:image, :video, :gallery]])
```

This guide should help update the failing tests to work with the new ref structure.
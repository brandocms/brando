# Brando CMS - Commands and Style Guide

## Build & Test Commands
- Install dependencies: `mix deps.get`
- Compile project: `mix compile`
- Run Elixir tests: `mix test`
- Run specific test: `mix test path/to/test_file.exs:line_number`
- Run end to end tests: `cd e2e/e2e_project && ./test_e2e.sh`
- Start e2e project server (for use with MCP): `cd e2e/e2e_project && ./run_e2e.sh` - the server starts on port 4444
- Code analysis:
  - Refactoring opportunities: `mix credo suggest --format json --all --only refactor`
  - Design: `mix credo suggest --format json --all --only design`
  - Readability: `mix credo suggest --format json --all --only readability`
  - Warnings: `mix credo suggest --format json --all --only warning`
  - Check single check example: `mix credo --format json --all --checks Credo.Check.Refactor.LongQuoteBlocks`
- Type checking: `mix dialyzer`
- Format code: `mix format`
- Reset database: `mix ecto.reset`
- Watch tests: `mix test.watch`

## Core Principles
- Write clean, concise, functional code using small, focused functions.
- **Explicit Over Implicit**: Prefer clarity over magic.
- **Single Responsibility**: Each module and function should do one thing well.
- **Easy to Change**: Design for maintainability and future change.
- **YAGNI**: Don't build features until they're needed.
- If any of my requests are not clear, ask me to clarify.
- If you have better suggestions, feel free to suggest them.

## LiveView, Phoenix and Ecto (+ Forms & Changesets)
- Use these technologies as intended

## Code Style Guidelines
- Follow Elixir style conventions
- Line length: 122 characters max (see .formatter.exs)
- Use descriptive variable and function names: e.g., `user_signed_in?`, `calculate_total`.
- Prefer higher-order functions and recursion over imperative loops.
- Use snake_case for variables and functions
- Module names in PascalCase
- Prefer pattern matching over conditionals
- Prefer using aliases over imports.
- Modules should have @moduledoc
- Public functions should have @doc
- Use explicit returns with :ok/:error tuples
- Import only what's needed with `import Ecto.Query, only: [from: 2]`
- Arrange Blueprint files with attributes, assets, relations, listings, forms
- Follow DSL conventions defined in .formatter.exs
- Follow standard Elixir practices and let `mix format <filename>` take care of formatting (run before committing code).

## Documentation and Quality
- Describe why, not what it does.
- **Document Public Functions**: Add `@doc` to all public functions.
- **Examples in Docs**: Include examples in documentation (as doctests when possible).
- **Cautious Refactoring**: Propose bug fixes or optimizations without changing behavior or unrelated code.
- **Comments**: Write comments only when information cannot be included in docs.

## Content Refs Architecture
- **Two-Layer Approach**: Refs use both block data (configuration/overrides) and asset associations (direct media references)
- **Polymorphic Data**: Ref's data field can contain various block types with specific configurations
- **Media Associations**: Refs can have direct associations to :image, :video, :gallery, and :file
- **Override Mechanism**: Block data overrides take precedence over base asset attributes when merging
- **Preloading Pattern**: Always preload refs with their associations: `preload: [:image, :video, gallery: [gallery_objects: [:image]]]`
- **Apply Ref Pattern**: Each block type implements `apply_ref` to handle syncing with module changes while preserving local customizations
- **Picture Block Merging**: Picture refs merge image data with block overrides (:title, :credits, :alt, :picture_class, :img_class, etc.)
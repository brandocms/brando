[
  inputs: [
    "lib/**/*.{ex,exs}",
    "test/**/*.{ex,exs}",
    "mix.exs"
  ],
  import_deps: [:ecto, :absinthe, :plug, :phoenix],
  locals_without_parens: [
    assert_reply: 2,
    assert_reply: 3,
    push: 3,
    defenum: :*,
    raw: :*,
    redirect: :*,
    # plug, plug_rest
    plug: 1,
    plug: 2,
    resource: 2,
    resource: 3,
    match: 2,
    pipe_through: :*,
    get: :*,
    put: :*,
    post: :*,
    delete: :*,
    forward: :*,
    # ecto
    belongs_to: :*,
    has_many: :*,
    has_one: :*,
    from: 2,
    field: :*,
    arg: :*,
    resolve: :*,
    parse: :*,
    serialize: :*,
    scalar: :*
  ],
  # rename_deprecated_at: "1.5.4"
]

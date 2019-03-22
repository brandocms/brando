use Mix.Config
alias Dogma.Rule

config :dogma,
  # Select a set of rules as a base
  rule_set: Dogma.RuleSet.All,
  exclude: [
    ~r(\Aconfig/),
    ~r(\Alib/\w+/endpoint.ex),
    ~r(priv/),
    ~r(tmp/),
    ~r(node_modules/),
    ~r(lib/mix/tasks/brando.install.ex),
    ~r(test/)
  ],
  # Override an existing rule configuration
  override: [
    %Rule.CommentFormat{enabled: false},
    %Rule.FunctionArity{enabled: true, max: 5},
    %Rule.MatchInCondition{enabled: false},
    %Rule.LineLength{enabled: true, max_length: 120},
    %Rule.PipelineStart{enabled: false},
    %Rule.QuotesInString{enabled: false}
  ]

defmodule Brando.Authorization.Rule do
  @moduledoc """
  The rule struct is based on CASL so we can pass a JSON
  version of our rules directly to Vue.

  ## Fields

  ### `action`

  - `create`
  - `read`
  - `update`
  - `delete`

  - `modify` = `create/read/update/delete`

  ### `subject`

  The entity to check against, i.e: "Page", "User", etc.
  Usually corresponds with entry's struct name

  ### `conditions`

  A map of conditions for the rule to pass, i.e
  %{status: :published}

  ### `inverted`

  If the rule should be inverted, in other words
  a "cannot" rule.

  # Example

  ```
  %Rule{
    action: :delete,
    subject: %Page{},
    conditions: %{status: :draft}
  }
  ```

  """
  @derive Jason.Encoder
  defstruct action: nil,
            subject: nil,
            conditions: nil,
            inverted: false

  def test_rule(
        %__MODULE__{action: :manage, subject: "all", inverted: false},
        action,
        _subject_struct,
        _subject,
        _acc
      )
      when action in [:create, :read, :update, :delete, :manage] do
    true
  end

  def test_rule(
        %__MODULE__{action: :manage, subject: "all", inverted: true},
        action,
        _subject_struct,
        _subject,
        _acc
      )
      when action in [:create, :read, :update, :delete, :manage] do
    false
  end

  # def test_rule(
  #       %__MODULE__{action: :manage, subject: rule_subject, inverted: true},
  #       action,
  #       subject_struct,
  #       subject,
  #       _acc
  #     )
  #     when action in [:create, :read, :update, :delete, :manage]
  #     when rule_subject == subject_struct do
  #   IO.inspect(rule_subject, label: "==> rule_subject == subject_struct", pretty: true)
  #   IO.inspect(action, label: "==> wanted action")
  #   false
  # end

  # :manage against all rules without conditions
  def test_rule(
        %{action: :manage, subject: rule_subject, inverted: inverted, conditions: nil},
        action,
        subject_struct,
        _subject,
        _acc
      )
      when rule_subject == subject_struct and
             action in [:manage, :create, :update, :read, :delete] do
    !inverted
  end

  # :manage against all rules with conditions
  def test_rule(
        %{action: :manage, subject: rule_subject, inverted: inverted, conditions: conditions},
        action,
        subject_struct,
        subject,
        acc
      )
      when rule_subject == subject_struct and
             action in [:manage, :create, :update, :read, :delete] do
    subject_conditions = Map.take(subject, Map.keys(conditions))

    if Map.equal?(subject_conditions, conditions) do
      !inverted
    else
      acc
    end
  end

  def test_rule(
        %{action: rule_action, subject: rule_subject, inverted: inverted, conditions: nil},
        action,
        subject_struct,
        _subject,
        _acc
      )
      when rule_subject == subject_struct and rule_action == action do
    !inverted
  end

  def test_rule(
        %{action: rule_action, subject: rule_subject, inverted: inverted, conditions: conditions},
        action,
        subject_struct,
        subject,
        acc
      )
      when rule_subject == subject_struct and rule_action == action do
    subject_conditions = Map.take(subject, Map.keys(conditions))

    if Map.equal?(subject_conditions, conditions) do
      !inverted
    else
      acc
    end
  end

  # pass through last value if no rule matches
  def test_rule(_, _, _, _, last_value), do: last_value
end

defmodule Brando.Authorization do
  @moduledoc """

  ## Example

      use Brando.Authorization

      types [
        {"User", Brando.Users.User},
        {"Page", Brando.Pages.Page},
        {"Fragment", Brando.Pages.Fragment}
      ]

      rules :superuser do
        can :manage, :all
      end

      rules :admin do
        can :manage, :all
        cannot :manage, "User", %{role: "superuser"}
      end
  """

  alias Brando.Authorization.Rule

  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :rules, accumulate: true)
      Module.register_attribute(__MODULE__, :types, accumulate: false)

      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      def get_rules_for(role) do
        role
        |> __rules__()
        |> Enum.map(
          &unquote(__MODULE__).denormalize_subject(
            &1,
            __MODULE__.__types__(:atom_to_binary)
          )
        )
      end

      defmodule Can do
        defmacro __using__(_) do
          quote do
            import unquote(__MODULE__)
          end
        end

        @moduledoc """
        can?(user, :delete, post)
        {:ok, :authorized}
        """
        @type user :: Brando.Users.User.t()
        @authorization_module __MODULE__ |> Module.split() |> Enum.drop(-1) |> Module.concat()

        @spec can?(user, atom, any) :: {:ok, :authorized} | {:error, :unauthorized}
        def can?(%Brando.Users.User{} = user, action, subject) do
          rules = @authorization_module.__rules__(user.role)

          case Enum.reduce(
                 rules,
                 false,
                 &Brando.Authorization.Rule.test_rule(
                   &1,
                   action,
                   subject.__struct__,
                   subject,
                   &2
                 )
               ) do
            true -> {:ok, :authorized}
            false -> {:error, :unauthorized}
          end
        end
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    rules = Module.get_attribute(env.module, :rules)

    types =
      env.module
      |> Module.get_attribute(:types)
      |> Enum.into(%{})

    types_reversed = Enum.into(types, %{}, &{elem(&1, 1), elem(&1, 0)})

    [compile_types(types, types_reversed), compile_rules(rules, types, types_reversed)]
  end

  @doc false
  def compile_types(types, types_reversed) do
    quote do
      def __types__(:binary_to_atom) do
        unquote(Macro.escape(types))
      end

      def __types__(:atom_to_binary) do
        unquote(Macro.escape(types_reversed))
      end
    end
  end

  # When we are dealing with rules inside Elixir, we want the subject stored as a
  # module atom, whenever possible.
  #
  # So if subject is a binary -> "User", we look it up in our types map and return
  # Brando.Users.User
  #
  # If the subject is a struct -> %Brando.Users.User, we grab the struct key (which
  # is a module atom) and return Brando.Users.User
  #
  # If the subject is not found in the types map, we store it as a binary. This is
  # useful for when we want to store rules that will only apply on the frontend,
  # for instance a "MenuItem".
  defp normalize_subject(%Rule{subject: :all} = rule, _, _), do: Map.put(rule, :subject, "all")

  defp normalize_subject(%Rule{subject: subject} = rule, types, _) when is_binary(subject),
    do: Map.put(rule, :subject, Map.get(types, subject, subject))

  defp normalize_subject(%Rule{subject: subject} = rule, _, _) when is_map(subject),
    do: Map.put(rule, :subject, subject.__struct__)

  def denormalize_subject(%Rule{subject: subject} = rule, _) when is_binary(subject), do: rule

  def denormalize_subject(%Rule{subject: subject} = rule, types) when is_atom(subject),
    do: Map.put(rule, :subject, Map.get(types, subject))

  @doc false
  def compile_rules(rules, types, types_reversed) do
    role_buckets =
      rules
      |> Keyword.keys()
      |> Enum.map(&{&1, []})
      |> Enum.into(%{})

    reduced_rules =
      Enum.reduce(rules, role_buckets, fn {role, rule}, acc ->
        Map.put(acc, role, [normalize_subject(rule, types, types_reversed) | Map.get(acc, role)])
      end)

    for {role, rules_for_role} <- reduced_rules do
      quote do
        def __rules__(unquote(role)) do
          unquote(Macro.escape(rules_for_role))
        end
      end
    end
  end

  defmacro types(types) do
    quote do
      @types unquote(types)
    end
  end

  defmacro rules(role, do: block) do
    quote do
      var!(role) = unquote(role)
      unquote(block)
    end
  end

  defmacro can(action, subject, opts \\ []) do
    subject = (is_map(subject) && subject.__struct__) || subject

    quote do
      role = unquote(Macro.var(:role, nil))

      action(
        role,
        unquote(action),
        unquote(subject),
        unquote(Keyword.get(opts, :when)),
        false
      )
    end
  end

  defmacro cannot(action, subject, opts \\ []) do
    quote do
      role = unquote(Macro.var(:role, nil))

      action(
        role,
        unquote(action),
        unquote(subject),
        unquote(Keyword.get(opts, :when)),
        true
      )
    end
  end

  defmacro action(role, action, subject, conditions, inverted) do
    quote do
      rule = %Brando.Authorization.Rule{
        action: unquote(action),
        subject: unquote(subject),
        conditions: unquote(conditions),
        inverted: unquote(inverted)
      }

      @rules {unquote(role), rule}
    end
  end
end

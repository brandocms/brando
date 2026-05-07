%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "src/", "web/", "apps/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      requires: [],
      check_for_updates: true,
      #
      # You can customize the parameters of any check by adding a second element
      # to the tuple.
      #
      # To disable a check put `false` as second element:
      #
      #     {Credo.Check.Design.DuplicatedCode, false}
      #
      checks: [
        {Credo.Check.Consistency.ExceptionNames},
        {Credo.Check.Consistency.LineEndings},
        {Credo.Check.Consistency.SpaceAroundOperators},
        {Credo.Check.Consistency.SpaceInParentheses},
        {Credo.Check.Consistency.TabsOrSpaces},
        {Credo.Check.Warning.ApplicationConfigInModuleAttribute, false},

        # For some checks, like AliasUsage, you can only customize the priority
        # Priority values are: `low, normal, high, higher`
        {Credo.Check.Design.AliasUsage, false},

        # For others you can set parameters

        # If you don't want the `setup` and `test` macro calls in ExUnit tests
        # or the `schema` macro in Ecto schemas to trigger DuplicatedCode, just
        # set the `excluded_macros` parameter to `[:schema, :setup, :test]`.
        {Credo.Check.Design.DuplicatedCode, excluded_macros: []},
        {Credo.Check.Design.TagTODO, false},
        {Credo.Check.Design.TagFIXME, false},
        {Credo.Check.Readability.FunctionNames},
        {Credo.Check.Readability.LargeNumbers},
        {Credo.Check.Readability.MaxLineLength, false},
        {Credo.Check.Readability.ModuleAttributeNames},
        # Until it is disabled for all .exs files
        {Credo.Check.Readability.ModuleDoc, false},
        {Credo.Check.Readability.ModuleNames},
        {Credo.Check.Readability.ParenthesesInCondition},
        {Credo.Check.Readability.PredicateFunctionNames},
        {Credo.Check.Readability.TrailingBlankLine},
        {Credo.Check.Readability.TrailingWhiteSpace},
        {Credo.Check.Readability.VariableNames},
        {Credo.Check.Readability.RedundantBlankLines},
        {Credo.Check.Refactor.ABCSize, false},
        {Credo.Check.Refactor.CondStatements},
        {Credo.Check.Refactor.FunctionArity},
        {Credo.Check.Refactor.MatchInCondition},
        {Credo.Check.Refactor.PipeChainStart, false},
        {Credo.Check.Refactor.CyclomaticComplexity},
        {Credo.Check.Refactor.NegatedConditionsInUnless},
        {Credo.Check.Refactor.NegatedConditionsWithElse},
        {Credo.Check.Refactor.Nesting},
        {Credo.Check.Refactor.UnlessWithElse},
        {Credo.Check.Warning.IExPry},
        {Credo.Check.Warning.IoInspect},

        # Those are warned by Elixir when it is ambiguous since Elixir v1.4
        {Credo.Check.Warning.OperationOnSameValues},
        {Credo.Check.Warning.BoolOperationOnSameValues},
        {Credo.Check.Warning.UnusedEnumOperation},
        {Credo.Check.Warning.UnusedKeywordOperation},
        {Credo.Check.Warning.UnusedListOperation},
        {Credo.Check.Warning.UnusedStringOperation},
        {Credo.Check.Warning.UnusedTupleOperation},
        {Credo.Check.Warning.OperationWithConstantResult},
        {Credo.Check.Refactor.MapInto, false},
        {Credo.Check.Warning.LazyLogging, false},

        # ExSlop
        {ExSlop.Check.Warning.BlanketRescue, []},
        {ExSlop.Check.Warning.RescueWithoutReraise, []},
        {ExSlop.Check.Warning.RepoAllThenFilter, []},
        {ExSlop.Check.Warning.QueryInEnumMap, []},
        {ExSlop.Check.Warning.GenserverAsKvStore, []},
        {ExSlop.Check.Warning.PathExpandPriv, []},
        {ExSlop.Check.Warning.DualKeyAccess, []},
        {ExSlop.Check.Refactor.FilterNil, []},
        {ExSlop.Check.Refactor.RejectNil, []},
        {ExSlop.Check.Refactor.ReduceAsMap, []},
        {ExSlop.Check.Refactor.MapIntoLiteral, []},
        {ExSlop.Check.Refactor.IdentityPassthrough, []},
        {ExSlop.Check.Refactor.IdentityMap, []},
        {ExSlop.Check.Refactor.CaseTrueFalse, []},
        {ExSlop.Check.Refactor.TryRescueWithSafeAlternative, []},
        {ExSlop.Check.Refactor.WithIdentityElse, []},
        {ExSlop.Check.Refactor.WithIdentityDo, []},
        {ExSlop.Check.Refactor.SortThenReverse, []},
        {ExSlop.Check.Refactor.StringConcatInReduce, []},
        {ExSlop.Check.Refactor.ReduceMapPut, []},
        {ExSlop.Check.Refactor.RedundantBooleanIf, []},
        {ExSlop.Check.Refactor.FlatMapFilter, []},
        {ExSlop.Check.Refactor.RedundantEnumJoinSeparator, []},
        {ExSlop.Check.Refactor.UseMapJoin, []},
        {ExSlop.Check.Refactor.PreferEnumSlice, []},
        {ExSlop.Check.Refactor.GraphemesLength, []},
        {ExSlop.Check.Refactor.ManualStringReverse, []},
        {ExSlop.Check.Refactor.SortThenAt, []},
        {ExSlop.Check.Refactor.SortForTopK, []},
        {ExSlop.Check.Refactor.ListFold, []},
        {ExSlop.Check.Refactor.ListLast, []},
        {ExSlop.Check.Refactor.LengthInGuard, []},
        {ExSlop.Check.Refactor.ExplicitSumReduce, []},
        {ExSlop.Check.Readability.NarratorDoc, []},
        {ExSlop.Check.Readability.DocFalseOnPublicFunction, []},
        {ExSlop.Check.Readability.BoilerplateDocParams, []},
        {ExSlop.Check.Readability.ObviousComment, [additional_keywords: []]},
        {ExSlop.Check.Readability.StepComment, []},
        {ExSlop.Check.Readability.NarratorComment, []},
        {ExSlop.Check.Readability.UnaliasedModuleUse, []}
      ]
    }
  ]
}

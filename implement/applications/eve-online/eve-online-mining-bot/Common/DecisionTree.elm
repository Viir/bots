module Common.DecisionTree exposing (..)


type DecisionPathNode leaf
    = DescribeBranch String (DecisionPathNode leaf)
    | EndDecisionPath leaf


endDecisionPath : leaf -> DecisionPathNode leaf
endDecisionPath =
    EndDecisionPath


describeBranch : String -> DecisionPathNode leaf -> DecisionPathNode leaf
describeBranch =
    DescribeBranch


unpackToDecisionStagesDescriptionsAndLeaf : DecisionPathNode leaf -> ( List String, leaf )
unpackToDecisionStagesDescriptionsAndLeaf node =
    case node of
        EndDecisionPath leaf ->
            ( [], leaf )

        DescribeBranch branchDescription childNode ->
            let
                ( childDecisionsDescriptions, leaf ) =
                    unpackToDecisionStagesDescriptionsAndLeaf childNode
            in
            ( branchDescription :: childDecisionsDescriptions, leaf )


continueDecisionTree : (originalLeaf -> DecisionPathNode newLeaf) -> DecisionPathNode originalLeaf -> DecisionPathNode newLeaf
continueDecisionTree continueLeaf originalNode =
    case originalNode of
        DescribeBranch branch childNode ->
            DescribeBranch branch (continueDecisionTree continueLeaf childNode)

        EndDecisionPath leaf ->
            continueLeaf leaf

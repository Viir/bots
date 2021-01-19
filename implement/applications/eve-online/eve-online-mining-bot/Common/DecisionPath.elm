module Common.DecisionPath exposing (..)


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


continueDecisionPath : (originalLeaf -> DecisionPathNode newLeaf) -> DecisionPathNode originalLeaf -> DecisionPathNode newLeaf
continueDecisionPath continueLeaf originalNode =
    case originalNode of
        DescribeBranch branch childNode ->
            DescribeBranch branch (continueDecisionPath continueLeaf childNode)

        EndDecisionPath leaf ->
            continueLeaf leaf

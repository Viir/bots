module Common.DecisionPath exposing (..)


type DecisionPathNode pathEnd
    = DescribeBranch String (DecisionPathNode pathEnd)
    | EndDecisionPath pathEnd


endDecisionPath : pathEnd -> DecisionPathNode pathEnd
endDecisionPath =
    EndDecisionPath


describeBranch : String -> DecisionPathNode pathEnd -> DecisionPathNode pathEnd
describeBranch =
    DescribeBranch


mapEnd : (oldEnd -> newEnd) -> DecisionPathNode oldEnd -> DecisionPathNode newEnd
mapEnd f node =
    case node of
        DescribeBranch branch childNode ->
            DescribeBranch branch (mapEnd f childNode)

        EndDecisionPath pathEnd ->
            EndDecisionPath (f pathEnd)


unpackToDecisionStagesDescriptionsAndLeaf : DecisionPathNode pathEnd -> ( List String, pathEnd )
unpackToDecisionStagesDescriptionsAndLeaf node =
    case node of
        EndDecisionPath pathEnd ->
            ( [], pathEnd )

        DescribeBranch branchDescription childNode ->
            let
                ( childDecisionsDescriptions, pathEnd ) =
                    unpackToDecisionStagesDescriptionsAndLeaf childNode
            in
            ( branchDescription :: childDecisionsDescriptions, pathEnd )


continueDecisionPath : (originalEnd -> DecisionPathNode newEnd) -> DecisionPathNode originalEnd -> DecisionPathNode newEnd
continueDecisionPath continuePath originalNode =
    case originalNode of
        DescribeBranch branch childNode ->
            DescribeBranch branch (continueDecisionPath continuePath childNode)

        EndDecisionPath pathEnd ->
            continuePath pathEnd

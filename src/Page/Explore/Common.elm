module Page.Explore.Common exposing (scopesView)

import Data.Scope as Scope exposing (Scope)
import Html exposing (..)
import Html.Attributes exposing (..)


scopesView : { a | scopes : List Scope } -> Html msg
scopesView =
    .scopes
        >> List.map
            (\scope ->
                span [ class "badge badge-success" ]
                    [ text <| Scope.toLabel scope ]
            )
        >> div [ class "d-flex gap-1" ]

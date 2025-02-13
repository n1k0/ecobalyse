module Page.Explore.TextileProducts exposing (table)

import Area
import Data.Dataset as Dataset
import Data.Env as Env
import Data.Scope exposing (Scope)
import Data.Split as Split
import Data.Textile.Db as TextileDb
import Data.Textile.DyeingMedium as DyeingMedium
import Data.Textile.Fabric as Fabric
import Data.Textile.Formula as Formula
import Data.Textile.Inputs as TextileInputs
import Data.Textile.LifeCycle as LifeCycle
import Data.Textile.MakingComplexity as MakingComplexity
import Data.Textile.Product as Product exposing (Product)
import Data.Textile.Simulator as Simulator
import Data.Textile.Step.Label as Label
import Data.Unit as Unit
import Duration
import Html exposing (..)
import Html.Attributes exposing (..)
import Mass
import Page.Explore.Table exposing (Table)
import Quantity
import Route
import Views.Format as Format
import Volume


withTitle : String -> Html msg
withTitle str =
    span [ title str ] [ text str ]


table : TextileDb.Db -> { detailed : Bool, scope : Scope } -> Table Product String msg
table db { detailed, scope } =
    { toId = .id >> Product.idToString
    , toRoute = .id >> Just >> Dataset.TextileProducts >> Route.Explore scope
    , rows =
        [ { label = "Identifiant"
          , toValue = .id >> Product.idToString
          , toCell =
                \product ->
                    if detailed then
                        code [] [ text (Product.idToString product.id) ]

                    else
                        a [ Route.href (Route.Explore scope (Dataset.TextileProducts (Just product.id))) ]
                            [ code [] [ text (Product.idToString product.id) ] ]
          }
        , { label = "Produit(s) concerné(s)"
          , toValue = .name
          , toCell = .name >> text
          }
        , { label = "Poids"
          , toValue = .mass >> Mass.inGrams >> String.fromFloat
          , toCell =
                \product ->
                    div [ classList [ ( "text-center", not detailed ) ] ]
                        [ Format.kg product.mass ]
          }
        , { label = "Titrage"
          , toValue = .yarnSize >> Unit.yarnSizeInKilometers >> String.fromInt
          , toCell =
                \product ->
                    div [ classList [ ( "text-center", not detailed ) ] ]
                        [ product.yarnSize |> Format.yarnSize ]
          }
        , { label = "Grammage"
          , toValue = .surfaceMass >> Unit.surfaceMassInGramsPerSquareMeters >> String.fromInt
          , toCell =
                \{ surfaceMass } ->
                    div [ classList [ ( "text-center", not detailed ) ] ]
                        [ Format.surfaceMass surfaceMass
                        ]
          }
        , let
            computeThreadDensity { surfaceMass, yarnSize } =
                yarnSize
                    |> Formula.computeThreadDensity surfaceMass
          in
          { label = "Densité de fils"
          , toValue = computeThreadDensity >> Unit.threadDensityToFloat >> String.fromFloat
          , toCell =
                computeThreadDensity >> Format.threadDensity
          }
        , let
            computeSurface { mass, surfaceMass } =
                Mass.inGrams mass
                    / toFloat (Unit.surfaceMassInGramsPerSquareMeters surfaceMass)
          in
          { label = "Surface"
          , toValue = computeSurface >> String.fromFloat
          , toCell = computeSurface >> Area.squareMeters >> Format.squareMeters
          }
        , { label = "Volume"
          , toValue = .endOfLife >> .volume >> Volume.inCubicMeters >> String.fromFloat
          , toCell =
                \product ->
                    div [ classList [ ( "text-center", not detailed ) ] ]
                        [ Format.m3 product.endOfLife.volume ]
          }
        , let
            fabricToString product =
                if Fabric.isKnitted product.fabric then
                    "Tricotée"

                else
                    "Tissée"
          in
          { label = "Etoffe"
          , toValue = fabricToString
          , toCell = fabricToString >> text
          }
        , let
            picking product surfaceMass ys =
                let
                    outputMass =
                        TextileInputs.defaultQuery
                            |> TextileInputs.updateProduct product
                            |> Simulator.compute db
                            |> Result.map (.lifeCycle >> LifeCycle.getStepProp Label.Fabric .outputMass Quantity.zero)
                            |> Result.withDefault Quantity.zero

                    outputSurface =
                        Unit.surfaceMassToSurface surfaceMass outputMass

                    threadDensity =
                        Formula.computeThreadDensity surfaceMass ys
                in
                outputSurface
                    |> Formula.computePicking threadDensity
          in
          { label = "Duites.m"
          , toValue =
                \({ surfaceMass, yarnSize } as product) ->
                    picking product surfaceMass yarnSize
                        |> Unit.pickPerMeterToFloat
                        |> String.fromFloat
          , toCell =
                \({ surfaceMass, yarnSize } as product) ->
                    div [ classList [ ( "text-center", not detailed ) ] ]
                        [ picking product surfaceMass yarnSize
                            |> Format.picking
                        ]
          }
        , let
            fadabaleToString product =
                if Product.isFadedByDefault product then
                    "oui"

                else
                    "non"
          in
          { label = "Délavage par défaut"
          , toValue = fadabaleToString
          , toCell =
                fadabaleToString >> text
          }
        , { label = "Stocks dormants"
          , toValue = Split.toPercentString Env.defaultDeadStock |> always
          , toCell =
                div [ classList [ ( "text-center", not detailed ) ] ]
                    [ Format.splitAsPercentage Env.defaultDeadStock ]
                    |> always
          }
        , { label = "Type de teinture"
          , toValue = .dyeing >> .defaultMedium >> DyeingMedium.toLabel
          , toCell = .dyeing >> .defaultMedium >> DyeingMedium.toLabel >> text
          }
        , { label = "Confection (complexité)"
          , toValue = .making >> .complexity >> MakingComplexity.toLabel
          , toCell = .making >> .complexity >> MakingComplexity.toLabel >> text
          }
        , { label = "Confection (# minutes)"
          , toValue = Product.getMakingDurationInMinutes >> Duration.inMinutes >> String.fromFloat
          , toCell =
                \product ->
                    div [ classList [ ( "text-center", not detailed ) ] ]
                        [ Product.getMakingDurationInMinutes product |> Format.minutes ]
          }
        , { label = "Confection (taux de perte)"
          , toValue = .making >> .pcrWaste >> Split.toPercentString
          , toCell =
                \product ->
                    div [ classList [ ( "text-center", not detailed ) ] ]
                        [ Format.splitAsPercentage product.making.pcrWaste ]
          }
        , { label = "Nombre de jours porté"
          , toValue = .use >> .daysOfWear >> Duration.inDays >> String.fromFloat
          , toCell =
                \product ->
                    div [ classList [ ( "text-center", not detailed ) ] ]
                        [ Format.days product.use.daysOfWear ]
          }
        , { label = "Utilisations avant lavage"
          , toValue = .use >> .wearsPerCycle >> String.fromInt
          , toCell =
                \product ->
                    div [ classList [ ( "text-center", not detailed ) ] ]
                        [ text <| String.fromInt product.use.wearsPerCycle ]
          }
        , { label = "Cycles d'entretien (par défaut)"
          , toValue = .use >> .defaultNbCycles >> String.fromInt
          , toCell =
                \product ->
                    div [ classList [ ( "text-center", not detailed ) ] ]
                        [ text <| String.fromInt product.use.defaultNbCycles ]
          }
        , { label = "Procédé de repassage"
          , toValue = .use >> .ironingProcess >> .name
          , toCell = .use >> .ironingProcess >> .name >> withTitle
          }
        , { label = "Procédé d'utilisation hors-repassage"
          , toValue = .use >> .nonIroningProcess >> .name
          , toCell = .use >> .nonIroningProcess >> .name >> withTitle
          }
        , { label = "Séchage électrique"
          , toValue = .use >> .ratioDryer >> Split.toPercentString
          , toCell =
                \product ->
                    div [ classList [ ( "text-center", not detailed ) ] ]
                        [ Format.splitAsPercentage product.use.ratioDryer ]
          }
        , { label = "Repassage (part)"
          , toValue = .use >> .ratioIroning >> Split.toPercentString
          , toCell =
                \product ->
                    div [ classList [ ( "text-center", not detailed ) ] ]
                        [ Format.splitAsPercentage product.use.ratioIroning ]
          }
        , { label = "Repassage (temps)"
          , toValue = .use >> .timeIroning >> Duration.inHours >> String.fromFloat
          , toCell =
                \product ->
                    div [ classList [ ( "text-center", not detailed ) ] ]
                        [ Format.hours product.use.timeIroning ]
          }
        ]
    }

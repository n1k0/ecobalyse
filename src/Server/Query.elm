module Server.Query exposing
    ( Errors
    , encodeErrors
    , parseFoodQuery
    , parseTextileQuery
    )

import Data.Country as Country exposing (Country)
import Data.Env as Env
import Data.Food.Db as FoodDb
import Data.Food.Process as FoodProcess
import Data.Food.Recipe as Recipe
import Data.Textile.Db as TextileDb
import Data.Textile.DyeingMedium as DyeingMedium exposing (DyeingMedium)
import Data.Textile.Inputs as Inputs
import Data.Textile.Material as Material exposing (Material)
import Data.Textile.Printing as Printing exposing (Printing)
import Data.Textile.Product as Product exposing (Product)
import Data.Textile.Step.Label as Label exposing (Label)
import Data.Unit as Unit
import Dict exposing (Dict)
import Json.Encode as Encode
import Mass exposing (Mass)
import Result.Extra as RE
import Url.Parser.Query as Query exposing (Parser)



-- Query String


type alias FieldName =
    String


type alias ErrorMessage =
    String


type alias Errors =
    Dict FieldName ErrorMessage


type alias ParseResult a =
    Result ( FieldName, String ) a


succeed : a -> Parser a
succeed =
    -- Kind of a hack: we don't have access to the Parser constructor, so
    -- we use Query.custom to wrap our thing in a Parser
    always >> Query.custom ""


parseFoodQuery : FoodDb.Db -> Parser (Result Errors Recipe.Query)
parseFoodQuery foodDb =
    succeed (Ok Recipe.Query)
        |> apply (ingredientListParser "ingredients" foodDb.processes)
        |> apply (maybeTransformParser "transform" foodDb.processes)
        |> apply (packagingListParser "packaging" foodDb.processes)
        |> apply (plantOptionsParser "plant")


ingredientListParser : String -> List FoodProcess.Process -> Parser (ParseResult (List Recipe.IngredientQuery))
ingredientListParser key ingredients =
    Query.custom (key ++ "[]")
        (List.map (ingredientParser ingredients)
            >> RE.combine
            >> Result.andThen validateIngredientList
            >> Result.mapError (\err -> ( key, err ))
        )


ingredientParser : List FoodProcess.Process -> String -> Result String Recipe.IngredientQuery
ingredientParser ingredients string =
    case String.split ";" string of
        [ code, mass ] ->
            Ok Recipe.IngredientQuery
                |> RE.andMap (foodProcessCodeParser ingredients code)
                |> RE.andMap (validateMass mass)
                -- TODO: parse country and labels
                |> RE.andMap (Ok Nothing)
                |> RE.andMap (Ok [])

        [ "" ] ->
            Err <| "Format d'ingrédient vide."

        _ ->
            Err <| "Format d'ingrédient invalide : " ++ string ++ "."


foodProcessCodeParser : List FoodProcess.Process -> String -> Result String FoodProcess.Code
foodProcessCodeParser ingredients string =
    string
        |> FoodProcess.codeFromString
        |> FoodProcess.findByCode ingredients
        |> Result.map .code


packagingListParser : String -> List FoodProcess.Process -> Parser (ParseResult (List Recipe.PackagingQuery))
packagingListParser key packagings =
    Query.custom (key ++ "[]")
        (List.map (packagingParser packagings)
            >> RE.combine
            >> Result.mapError (\err -> ( key, err ))
        )


packagingParser : List FoodProcess.Process -> String -> Result String Recipe.PackagingQuery
packagingParser packagings string =
    case String.split ";" string of
        [ code, mass ] ->
            Ok Recipe.PackagingQuery
                |> RE.andMap (foodProcessCodeParser packagings code)
                |> RE.andMap (validateMass mass)

        [ "" ] ->
            Err <| "Format d'emballage vide."

        _ ->
            Err <| "Format d'emballage invalide : " ++ string ++ "."


validateMass : String -> Result String Mass
validateMass string =
    string
        |> String.toFloat
        |> Result.fromMaybe ("Masse invalide : " ++ string)
        |> Result.andThen
            (\mass ->
                if mass < 0 then
                    Err "La masse doit être supérieure ou égale à zéro."

                else
                    Ok mass
            )
        |> Result.map Mass.grams


validateIngredientList : List Recipe.IngredientQuery -> Result String (List Recipe.IngredientQuery)
validateIngredientList list =
    if list == [] then
        Err "La liste des ingrédients est vide."

    else
        Ok list


maybeTransformParser : String -> List FoodProcess.Process -> Parser (ParseResult (Maybe Recipe.TransformQuery))
maybeTransformParser key transforms =
    Query.string key
        |> Query.map
            (Maybe.map
                (\str ->
                    parseTransform_ transforms str
                        |> Result.map Just
                        |> Result.mapError (\err -> ( key, err ))
                )
                >> Maybe.withDefault (Ok Nothing)
            )


parseTransform_ : List FoodProcess.Process -> String -> Result String Recipe.TransformQuery
parseTransform_ transforms string =
    case String.split ";" string of
        [ code, mass ] ->
            Ok Recipe.TransformQuery
                |> RE.andMap (foodProcessCodeParser transforms code)
                |> RE.andMap (validateMass mass)

        [ "" ] ->
            Err <| "Code de procédé de transformation manquant."

        _ ->
            Err <| "Format de procédé de transformation invalide : " ++ string ++ "."


plantOptionsParser : String -> Parser (ParseResult Recipe.PlantOptions)
plantOptionsParser _ =
    -- TODO: implement parsing when we actually need these options
    succeed (Ok { country = Nothing })


parseTextileQuery : TextileDb.Db -> Parser (Result Errors Inputs.Query)
parseTextileQuery textileDb =
    succeed (Ok Inputs.Query)
        |> apply (massParser "mass")
        |> apply (materialListParser "materials" textileDb.materials)
        |> apply (productParser "product" textileDb.products)
        |> apply (maybeCountryParser "countrySpinning" textileDb.countries)
        |> apply (countryParser "countryFabric" textileDb.countries)
        |> apply (countryParser "countryDyeing" textileDb.countries)
        |> apply (countryParser "countryMaking" textileDb.countries)
        |> apply (maybeRatioParser "airTransportRatio")
        |> apply (maybeQualityParser "quality")
        |> apply (maybeReparabilityParser "reparability")
        |> apply (maybeMakingWasteParser "makingWaste")
        |> apply (maybePickingParser "picking")
        |> apply (maybeSurfaceMassParser "surfaceMass")
        |> apply (maybeDisabledStepsParser "disabledSteps")
        |> apply (maybeBoolParser "disabledFading")
        |> apply (maybeDyeingMedium "dyeingMedium")
        |> apply (maybePrinting "printing")


toErrors : ParseResult a -> Result Errors a
toErrors =
    Result.mapError
        (\( key, errorMessage ) ->
            Dict.singleton key errorMessage
        )


builder :
    Result (Dict comparable v) a
    -> Result (Dict comparable v) (a -> b)
    -> Result (Dict comparable v) b
builder result accumulator =
    case ( result, accumulator ) of
        ( Err a, Err b ) ->
            -- Merge the error dicts
            Err <| Dict.union a b

        ( Ok _, Err b ) ->
            -- No error in "result", but the accumulator is errored: return the errored accumulator
            Err b

        ( valueOrError, Ok fn ) ->
            Result.map fn valueOrError


apply : Parser (ParseResult a) -> Parser (Result Errors (a -> b)) -> Parser (Result Errors b)
apply argParser funcParser =
    -- Adapted from https://package.elm-lang.org/packages/elm/url/latest/Url-Parser-Query#map8
    -- with the full list of errors returned, instead of just the first one encountered.
    Query.map2
        builder
        (Query.map toErrors argParser)
        funcParser


floatParser : String -> Parser (Maybe Float)
floatParser key =
    Query.custom key <|
        \stringList ->
            case stringList of
                [ str ] ->
                    String.toFloat str

                _ ->
                    Nothing


massParser : String -> Parser (ParseResult Mass)
massParser key =
    floatParser key
        |> Query.map (Result.fromMaybe ( key, "La masse est manquante." ))
        |> Query.map
            (Result.andThen
                (\mass ->
                    if mass < 0 then
                        Err ( key, "La masse doit être supérieure ou égale à zéro." )

                    else
                        Ok <| Mass.kilograms mass
                )
            )


productParser : String -> List Product -> Parser (ParseResult Product.Id)
productParser key products =
    Query.string key
        |> Query.map (Result.fromMaybe ( key, "Identifiant du type de produit manquant." ))
        |> Query.map
            (Result.andThen
                (\id ->
                    products
                        |> Product.findById (Product.Id id)
                        |> Result.map .id
                        |> Result.mapError (\err -> ( key, err ))
                )
            )


materialListParser : String -> List Material -> Parser (ParseResult (List Inputs.MaterialQuery))
materialListParser key materials =
    Query.custom (key ++ "[]")
        (List.map (parseMaterial_ materials)
            >> RE.combine
            >> Result.andThen validateMaterialList
            >> Result.mapError (\err -> ( key, err ))
        )


parseMaterial_ : List Material -> String -> Result String Inputs.MaterialQuery
parseMaterial_ materials string =
    case String.split ";" string of
        [ id, share ] ->
            Ok Inputs.MaterialQuery
                |> RE.andMap (parseMaterialId_ materials id)
                |> RE.andMap (parseRatio_ share)

        [ "" ] ->
            Err <| "Format de matière vide."

        _ ->
            Err <| "Format de matière invalide : " ++ string ++ "."


parseMaterialId_ : List Material -> String -> Result String Material.Id
parseMaterialId_ materials string =
    materials
        |> Material.findById (Material.Id string)
        |> Result.map .id


parseRatio_ : String -> Result String Unit.Ratio
parseRatio_ string =
    string
        |> String.toFloat
        |> Result.fromMaybe ("Ratio invalide : " ++ string)
        |> Result.andThen
            (\ratio ->
                if ratio < 0 || ratio > 1 then
                    Err <|
                        "Un ratio doit être compris entre 0 et 1 inclus (ici : "
                            ++ String.fromFloat ratio
                            ++ ")."

                else
                    Ok ratio
            )
        |> Result.map Unit.ratio


validateMaterialList : List Inputs.MaterialQuery -> Result String (List Inputs.MaterialQuery)
validateMaterialList list =
    if list == [] then
        Err "La liste des matières est vide."

    else
        let
            total =
                list |> List.map (.share >> Unit.ratioToFloat) |> List.sum
        in
        if total /= 1 then
            Err <|
                "La somme des parts de matières doit être égale à 1 (ici : "
                    ++ String.fromFloat total
                    ++ ")"

        else
            Ok list


countryParser : String -> List Country -> Parser (ParseResult Country.Code)
countryParser key countries =
    Query.string key
        |> Query.map (Result.fromMaybe ( key, "Code pays manquant." ))
        |> Query.map
            (Result.andThen
                (\code ->
                    countries
                        |> Country.findByCode (Country.Code code)
                        |> Result.map .code
                        |> Result.mapError (\err -> ( key, err ))
                )
            )


maybeCountryParser : String -> List Country -> Parser (ParseResult (Maybe Country.Code))
maybeCountryParser key countries =
    Query.string key
        |> Query.map
            (Maybe.map
                (\code ->
                    countries
                        |> Country.findByCode (Country.Code code)
                        |> Result.map (.code >> Just)
                        |> Result.mapError (\err -> ( key, err ))
                )
                >> Maybe.withDefault (Ok Nothing)
            )


maybeDyeingMedium : String -> Parser (ParseResult (Maybe DyeingMedium))
maybeDyeingMedium key =
    Query.string key
        |> Query.map
            (Maybe.map
                (\str ->
                    case DyeingMedium.fromString str of
                        Ok dyeingMedium ->
                            Ok (Just dyeingMedium)

                        Err err ->
                            Err ( key, err )
                )
                >> Maybe.withDefault (Ok Nothing)
            )


maybePrinting : String -> Parser (ParseResult (Maybe Printing))
maybePrinting key =
    Query.string key
        |> Query.map
            (Maybe.map
                (\str ->
                    case Printing.fromString str of
                        Ok printing ->
                            Ok (Just printing)

                        Err err ->
                            Err ( key, err )
                )
                >> Maybe.withDefault (Ok Nothing)
            )


maybeRatioParser : String -> Parser (ParseResult (Maybe Unit.Ratio))
maybeRatioParser key =
    floatParser key
        |> Query.map
            (Maybe.map
                (\float ->
                    if float < 0 || float > 1 then
                        Err ( key, "Un ratio doit être compris entre 0 et 1 inclus." )

                    else
                        Ok (Just (Unit.ratio float))
                )
                >> Maybe.withDefault (Ok Nothing)
            )


maybeQualityParser : String -> Parser (ParseResult (Maybe Unit.Quality))
maybeQualityParser key =
    floatParser key
        |> Query.map
            (Maybe.map
                (\float ->
                    let
                        ( min, max ) =
                            ( Unit.qualityToFloat Unit.minQuality
                            , Unit.qualityToFloat Unit.maxQuality
                            )
                    in
                    if float < min || float > max then
                        Err
                            ( key
                            , "Le coefficient de qualité intrinsèque doit être compris entre "
                                ++ String.fromFloat min
                                ++ " et "
                                ++ String.fromFloat max
                                ++ "."
                            )

                    else
                        Ok (Just (Unit.quality float))
                )
                >> Maybe.withDefault (Ok Nothing)
            )


maybeReparabilityParser : String -> Parser (ParseResult (Maybe Unit.Reparability))
maybeReparabilityParser key =
    floatParser key
        |> Query.map
            (Maybe.map
                (\float ->
                    let
                        ( min, max ) =
                            ( Unit.reparabilityToFloat Unit.minReparability
                            , Unit.reparabilityToFloat Unit.maxReparability
                            )
                    in
                    if float < min || float > max then
                        Err
                            ( key
                            , "Le coefficient de réparabilité doit être compris entre "
                                ++ String.fromFloat min
                                ++ " et "
                                ++ String.fromFloat max
                                ++ "."
                            )

                    else
                        Ok (Just (Unit.reparability float))
                )
                >> Maybe.withDefault (Ok Nothing)
            )


maybeMakingWasteParser : String -> Parser (ParseResult (Maybe Unit.Ratio))
maybeMakingWasteParser key =
    floatParser key
        |> Query.map
            (Maybe.map
                (\float ->
                    if float < Unit.ratioToFloat Env.minMakingWasteRatio || float > Unit.ratioToFloat Env.maxMakingWasteRatio then
                        Err
                            ( key
                            , "Le taux de perte en confection doit être compris entre "
                                ++ String.fromFloat (Unit.ratioToFloat Env.minMakingWasteRatio)
                                ++ " et "
                                ++ String.fromFloat (Unit.ratioToFloat Env.maxMakingWasteRatio)
                                ++ "."
                            )

                    else
                        Ok (Just (Unit.ratio float))
                )
                >> Maybe.withDefault (Ok Nothing)
            )


maybePickingParser : String -> Parser (ParseResult (Maybe Unit.PickPerMeter))
maybePickingParser key =
    Query.int key
        |> Query.map
            (Maybe.map
                (\int ->
                    if
                        (int < Unit.pickPerMeterToInt Unit.minPickPerMeter)
                            || (int > Unit.pickPerMeterToInt Unit.maxPickPerMeter)
                    then
                        Err
                            ( key
                            , "Le duitage (picking) doit être compris entre "
                                ++ String.fromInt (Unit.pickPerMeterToInt Unit.minPickPerMeter)
                                ++ " et "
                                ++ String.fromInt (Unit.pickPerMeterToInt Unit.maxPickPerMeter)
                                ++ " duites/m."
                            )

                    else
                        Ok (Just (Unit.pickPerMeter int))
                )
                >> Maybe.withDefault (Ok Nothing)
            )


maybeSurfaceMassParser : String -> Parser (ParseResult (Maybe Unit.SurfaceMass))
maybeSurfaceMassParser key =
    Query.int key
        |> Query.map
            (Maybe.map
                (\int ->
                    if
                        (int < Unit.surfaceMassToInt Unit.minSurfaceMass)
                            || (int > Unit.surfaceMassToInt Unit.maxSurfaceMass)
                    then
                        Err
                            ( key
                            , "Le grammage (surfaceMass) doit être compris entre "
                                ++ String.fromInt (Unit.surfaceMassToInt Unit.minSurfaceMass)
                                ++ " et "
                                ++ String.fromInt (Unit.surfaceMassToInt Unit.maxSurfaceMass)
                                ++ " gr/m²."
                            )

                    else
                        Ok (Just (Unit.surfaceMass int))
                )
                >> Maybe.withDefault (Ok Nothing)
            )


maybeDisabledStepsParser : String -> Parser (ParseResult (List Label))
maybeDisabledStepsParser key =
    Query.string key
        |> Query.map
            (Maybe.map
                (\str ->
                    str
                        |> String.split ","
                        |> List.map Label.fromCodeString
                        |> RE.combine
                        |> Result.mapError
                            (\err ->
                                ( key
                                , "Impossible d'interpréter la liste des étapes désactivées; " ++ err
                                )
                            )
                )
                >> Maybe.withDefault (Ok [])
            )


maybeBoolParser : String -> Parser (ParseResult (Maybe Bool))
maybeBoolParser key =
    Query.string key
        |> Query.map
            (Maybe.map
                (\str ->
                    case str of
                        "true" ->
                            Ok (Just True)

                        "false" ->
                            Ok (Just False)

                        _ ->
                            Err ( key, "La valeur ne peut être que true ou false." )
                )
                >> Maybe.withDefault (Ok Nothing)
            )



-- Encoders


encodeErrors : Errors -> Encode.Value
encodeErrors errors =
    Encode.object
        [ ( "errors"
          , errors
                |> Encode.dict identity Encode.string
          )
        ]

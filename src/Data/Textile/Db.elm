module Data.Textile.Db exposing
    ( Db
    , buildFromJson
    )

import Data.Country as Country exposing (Country)
import Data.Impact as Impact
import Data.Impact.Definition as Definition exposing (Definitions)
import Data.Textile.Material as Material exposing (Material)
import Data.Textile.Process as TextileProcess
import Data.Textile.Product as Product exposing (Product)
import Data.Transport as Transport exposing (Distances)
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Extra as DE


type alias Db =
    { impactDefinitions : Definitions
    , processes : List TextileProcess.Process
    , countries : List Country
    , materials : List Material
    , products : List Product
    , transports : Distances
    , wellKnown : TextileProcess.WellKnown
    }


buildFromJson : String -> String -> Result String Db
buildFromJson processesJson json =
    processesJson
        |> Decode.decodeString (TextileProcess.decodeList Impact.decodeImpacts)
        |> Result.andThen
            (\processes ->
                json
                    |> Decode.decodeString (decode processes)
            )
        |> Result.mapError Decode.errorToString


decode : List TextileProcess.Process -> Decoder Db
decode processes =
    Decode.field "impacts" Definition.decode
        |> Decode.andThen
            (\definitions ->
                Decode.map4 (Db definitions processes)
                    (Decode.field "countries" (Country.decodeList processes))
                    (Decode.field "materials" (Material.decodeList processes))
                    (Decode.field "products" (Product.decodeList processes))
                    (Decode.field "transports" Transport.decodeDistances)
                    |> Decode.andThen
                        (\partiallyLoaded ->
                            TextileProcess.loadWellKnown processes
                                |> Result.map partiallyLoaded
                                |> DE.fromResult
                        )
            )

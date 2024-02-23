# Script to add activities to activities.json from a csv ("sensitive_import.csv")
import pandas as pd
import json

# input/output

SENSITIVE_IMPORT = "sensitive_import.csv"
TEMP = "sensitive_import_T.csv"
ACTIVITIES = "../activities.json"

impact_trigram = {
    "Acidification": "acd",
    "Climate change": "cch",
    "Ecotoxicity, freshwater": "etf",
    "Particulate matter": "pma",
    "Eutrophication, marine": "swe",
    "Eutrophication, freshwater": "fwe",
    "Eutrophication, terrestrial": "tre",
    "Human toxicity, cancer": "htc",
    "Human toxicity, non-cancer": "htn",
    "Ionising radiation": "ior",
    "Land use": "ldu",
    "Ozone depletion": "ozd",
    "Photochemical ozone formation": "pco",
    "Resource use, fossils": "fru",
    "Resource use, minerals and metals": "mru",
    "Water use": "wtu",
}


def load_sensitive_import(sensitive_import_path):
    # Transpose the dataframe
    df = pd.read_csv(sensitive_import_path)
    df = df.T
    df.to_csv(TEMP, header=False)
    # Read the transposed dataframe and convert it to a dictionary
    df = pd.read_csv(TEMP)
    df = df.set_index("id")
    df = df.drop(index="ignore")
    activities_to_add = df.to_dict("index")
    return activities_to_add


if __name__ == "__main__":

    activities_to_add = load_sensitive_import(SENSITIVE_IMPORT)
    with open(ACTIVITIES, "r") as f:
        activities = json.load(f)

    # Add the activities from sensitive_import to activities.json

    for id, values in activities_to_add.items():
        if id not in [act["id"] for act in activities]:
            activities.append(
                {
                    "id": id,
                    "name": values["name"],
                    "search": values["search"],
                    "category": values["category"],
                    "categories": [values["categories"]],
                    "default_origin": values["default_origin"],
                    "raw_to_cooked_ratio": values["raw_to_cooked_ratio"],
                    "density": values["density"],
                    "inedible_part": values["inedible_part"],
                    "transport_cooling": values["transport_cooling"],
                    "land_footprint": values["land_footprint"],
                    "crop_group": values["crop_group"],
                    "scenario": values["scenario"],
                    "visible": values["visible"],
                    "impact_computed_from": values["impact_computed_from"],
                }
            )

    with open(ACTIVITIES, "w") as f:
        json.dump(activities, f, ensure_ascii=False, indent=4)

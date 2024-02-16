import urllib
import json
import requests
from common.export import cached_search

ACTIVITIES = "activities.json"
AGRIBALYSE = "Agribalyse 3.1.1"


if __name__ == "__main__":
    with open(ACTIVITIES, "r") as f:
        activities = json.load(f)

    for activity in activities:
        process_name = cached_search(
            activity.get("database", AGRIBALYSE), activity["search"]
        )
        process = urllib.parse.quote(process_name, encoding=None, errors=None)
        spsurface = json.loads(
            requests.get(
                f"http://simapro.ecobalyse.fr:8000/surface?process={process}"
            ).content
        )["surface"]
        activity["land_occupation"] = spsurface
        print(f"Computed land occupation for {process_name}")

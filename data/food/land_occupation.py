import urllib
import json
import requests
from common.export import cached_search
from bw2data.project import projects

ACTIVITIES = "activities.json"
AGRIBALYSE = "Agribalyse 3.1.1"
PROJECT = "food"


if __name__ == "__main__":
    projects.set_current(PROJECT)
    with open(ACTIVITIES, "r") as f:
        activities = json.load(f)

    for activity in activities:
        process = cached_search(
            activity.get("database", AGRIBALYSE), activity["search"]
        )
        process = urllib.parse.quote(process["name"], encoding=None, errors=None)
        spsurface = json.loads(
            requests.get(
                f"http://simapro.ecobalyse.fr:8000/surface?process={process}"
            ).content
        )["surface"]
        activity["land_occupation"] = spsurface
        print(f"Computed land occupation for {process['name']}, value: {spsurface}")

    with open(ACTIVITIES, "w") as outfile:
        json.dump(activities, outfile, indent=2, ensure_ascii=False)


#!/usr/bin/python3

import urllib.request, urllib.error
import json
import time
import re

class CommunicationBreakdown(Exception): pass

class BusRequester(object):

    def __init__(self, key, url_prefix):
        self.key = key
        assert url_prefix.endswith("/api/")
        self.url_prefix = url_prefix

    def _get(self, url, strip_top_level, name_map):
        while True:
            try:
                req = urllib.request.urlopen(url)
                break
            except urllib.error.HTTPError as exc:
                print(url)
                print(exc)
                time.sleep(300)

        assert req.code == 200
        response = req.read()
        doc = json.loads(response.decode("UTF-8"))

        try:
            data = doc["bustime-response"][strip_top_level]
        except KeyError:
            raise CommunicationBreakdown(url, [e["msg"] for e in doc["bustime-response"]["error"]])
        return [dict((name_map[k], v) for k, v in d.items()) for d in data]

    def get_routes(self):
        url = "{self.url_prefix}v2/getroutes?format=json&key={self.key}".format(**locals())
        name_map = { "rt": "id", "rtnm": "name", "rtclr": "color", "rtdd": "dd" }
        return self._get(url, "routes", name_map)

    def get_route_directions(self, route_id):
        url = "{self.url_prefix}v2/getdirections?format=json&rt={route_id}&key={self.key}".format(**locals())
        name_map = { "dir": "id", "name": "name" }
        return self._get(url, "directions", name_map)

    def get_route_direction_stops(self, route_id, direction_id):
        url = "{self.url_prefix}v2/getstops?format=json&rt={route_id}&dir={direction_id}&key={self.key}".format(**locals())
        name_map = { "stpid": "id", "stpnm": "name", "lat": "lat", "lon": "lng" }
        return self._get(url, "stops", name_map)

    def get_route_patterns(self, route_id):
        url = "{self.url_prefix}v2/getpatterns?format=json&rt={route_id}&key={self.key}".format(**locals())
        name_map = { "pid": "id", "ln": "length-in-feet", "rtdir": "direction", "pt": "points" }
        return self._get(url, "ptr", name_map)



with open("secret-key") as f:
    api_key = f.read().strip()
url_prefix = "http://lynxbustracker.com/bustime/api/"
br = BusRequester(api_key, url_prefix)

routes = dict()
stops = dict()

for route_info in br.get_routes():
    route_name = re.sub(r"Us\b", "US", route_info["name"].title()).strip()
    route_id = int(route_info["id"].strip())

    routes[route_id] = route_info.copy()
    routes[route_id].pop("id")
    routes[route_id]["direction-patterns"] = list()
    routes[route_id]["direction-stops"] = dict()
    routes[route_id]["human-name"] = re.sub("^LYMMO-|^LINK ", "", routes[route_id]["name"]).lower()

    for pattern_info in br.get_route_patterns(route_id):
        patt = dict()
        patt["direction"] = pattern_info["direction"]
        patt["points"] = list()

        for point_info in pattern_info["points"]:
            nicer_info = dict()
            nicer_info["sequence-number"] = int(point_info["seq"])
            nicer_info["latitude"] = point_info["lat"]
            nicer_info["longitude"] = point_info["lon"]
            if "stpid" in point_info:
                nicer_info["stop-id"] = point_info["stpid"]
            patt["points"].append(nicer_info)
            
        patt["points"].sort(key=lambda pi: pi["sequence-number"])

        print(patt)
        routes[route_id]["direction-patterns"].append(patt)

    for direction_info in br.get_route_directions(route_id):
        direction_id = direction_info["id"]
        direction_id = direction_info["id"]
        routes[route_id]["direction-stops"][direction_id] = list()
        #direction_info["dir"] = direction_info["dir"].lower().replace(" + ", " × ")

        for stop_info in br.get_route_direction_stops(route_id, direction_id.replace(" ", "%20")):
            stop_id = stop_info["id"]
            routes[route_id]["direction-stops"][direction_id].append(stop_id)

            if stop_id not in stops:
                stops[stop_id] = dict()
                stops[stop_id]["routes_interacting"] = list()

            s = stops[stop_id]
            s["routes_interacting"].append((str(route_id), direction_info["id"]))
            s["latitude"] = stop_info["lat"]
            s["longitude"] = stop_info["lng"]
            s["human_name"] = re.sub(r"Us\b", "US", stop_info["name"].title().replace(" + ", " × ")).replace("Lcs", "Lynx Central Station")


with open("routes.json", "w") as dumpfile:
    json.dump(routes, dumpfile, indent=3)

with open("stops.json", "w") as dumpfile:
    json.dump(stops, dumpfile, indent=3)

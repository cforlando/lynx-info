#!/usr/bin/python2
# coding: UTF-8

from __future__ import print_function
try:
    import urllib.request, urllib.error
    HTTPError = urllib.error.HTTPError
except ImportError:
    import urllib2 as urllib
    HTTPError = urllib.HTTPError
import json
import time
import re
import sqlite3
import datetime
import pytz


class CommunicationBreakdown(Exception): pass

class BusRequester(object):

    def __init__(self, key, url_prefix):
        self.key = key
        assert url_prefix.endswith("/api/")
        self.url_prefix = url_prefix
        self.query_count = 0

    def _get(self, url, strip_top_level, name_map):
        while True:
            try:
                req = urllib.urlopen(url)
                self.query_count += 1
                break
            except HTTPError as exc:
                print(url)
                print(exc)
                time.sleep(300)

        assert req.code == 200
        response = req.read()
        doc = json.loads(response.decode("UTF-8"))

        try:
            data = doc["bustime-response"][strip_top_level]
        except KeyError:
            data = []
        return [dict((name_map.get(k, k), v) for k, v in d.items()) for d in data], doc["bustime-response"].get("error")

    def get_routes(self):
        url = "{self.url_prefix}v2/getroutes?format=json&key={self.key}".format(**locals())
        name_map = { "rt": "route_id", "rtnm": "name", "rtclr": "suggested_color_rrbbgg", "rtdd": "dd" }
        return self._get(url, "routes", name_map)

    def get_route_directions(self, route_id):
        url = "{self.url_prefix}v2/getdirections?format=json&rt={route_id}&key={self.key}".format(**locals())
        name_map = { "dir": "dir", "name": "name" }
        return self._get(url, "directions", name_map)

    def get_route_direction_stops(self, route_id, direction_id):
        url = "{self.url_prefix}v2/getstops?format=json&rt={route_id}&dir={direction_id}&key={self.key}".format(**locals())
        name_map = { "stpid": "stop_id", "stpnm": "name", "lat": "lat", "lon": "lng" }
        return self._get(url, "stops", name_map)

    def get_stops_predictions(self, stop_ids):
        stops = ",".join(stop_ids)
        url = "{self.url_prefix}v2/getpredictions?format=json&stpid={stops}&key={self.key}".format(**locals())
        name_map = { "prdtm": "predicted_time", "dly": "is_delayed", "rtdir": "direction", "rt": "route_id", "des": "destination", "rtdd": "dd", "tmstmp": "timestamp", "vid": "vehicle_id", "stpnm": "stop_name", "stpid": "stop_id", "dstp": "dstp", "zone": "zone", "tablockid": "tablockid", "prdctdn": "prdctdn" }
        return self._get(url, "prd", name_map)



tz = pytz.timezone("America/New_York")
utc = pytz.timezone("UTC")
epoch = utc.localize(datetime.datetime(1970, 1, 1))
server_now = utc.localize(datetime.datetime.utcnow())

with open("secret-key") as f:
    api_key = f.read().strip()
url_prefix = "http://lynxbustracker.com/bustime/api/"
br = BusRequester(api_key, url_prefix)

db_connection = sqlite3.connect('/home/protected/web-owned/lynx-proxy.sqlite3', isolation_level=None)
cursor = db_connection.cursor()


def datetime_to_epochms(t):
    delta = t - epoch
    return int(delta.total_seconds() * 1000)


try:
    cursor.execute("SELECT stop_id, due FROM cache_sched WHERE due < ?", (server_now,))
except sqlite3.Error:
    collected = set()
    for route_info in br.get_routes()[0]:
        route_name = re.sub(r"Us\b", "US", route_info["name"].title())
        for direction_info in br.get_route_directions(route_info["route_id"])[0]:
            for stop_info in br.get_route_direction_stops(route_info["route_id"], direction_info["dir"].replace(" ", "%20"))[0]:
                collected.add(stop_info["stop_id"])

    cursor.execute("CREATE TABLE cache_sched (stop_id char(5) PRIMARY key, due TEXT)")
    for s in collected:
        cursor.execute("INSERT INTO cache_sched (stop_id, due) VALUES (?, ?)", (s, server_now,))

    cursor.execute("SELECT stop_id, due FROM cache_sched LIMIT 10", (server_now,))

all_ids_and_dues = cursor.fetchall()
all_stop_ids = [ row[0] for row in all_ids_and_dues ]

for i in range(0, len(all_stop_ids), 10):

    stop_ids = all_stop_ids[i:i+10]

    if len(stop_ids) < 7:
        continue

    stops_infos, errors = br.get_stops_predictions(stop_ids)

    cursor.execute("begin")

    for stop_id in stop_ids:
        cursor.execute("DELETE FROM predictions WHERE stop_id = ?", (stop_id,))

    if errors:
        for s in errors:
            next_check = server_now + datetime.timedelta(minutes=30)
            if "stpid" in s:
                cursor.execute("INSERT OR REPLACE INTO cache_sched (stop_id, due) VALUES (?, ?)", (s["stpid"], next_check))
            else:
                print(s)

    if stops_infos:
        for s in stops_infos:
            try:
                # translate string to UTC immediately
                naivept = datetime.datetime.strptime(s["predicted_time"], "%Y%m%d %H:%M")
                localpt = tz.localize(naivept)
                pt = localpt.astimezone(utc)

                until_arrive = pt - server_now

                if until_arrive < datetime.timedelta(minutes=-10):   # older than 10 min in past?!
                    print("stop id {stop_id} is tragically stale. We think it arrived {predicted_time}. Deferring checking because something is wrong.".format(**s))
                    print("it arrives in {} minutes".format(until_arrive.total_seconds() / 60))
                    until_arrive = datetime.timedelta(minutes=20)

                next_check = server_now + datetime.timedelta(seconds=(until_arrive.total_seconds() / 3 * 2))

                cursor.execute("INSERT OR REPLACE INTO cache_sched (stop_id, due) VALUES (?, ?)", (s["stop_id"], max(server_now, next_check)))

                cursor.execute(u"INSERT INTO predictions (stop_id, predicted_time_ms, is_delayed, direction, route_id, destination, insert_time_ms) VALUES (?, ?, ?, ?, ?, ?, ?)", (s["stop_id"], datetime_to_epochms(pt), s["is_delayed"], s["direction"].lower(), s["route_id"], s["destination"].title().replace(" Us ", " US ").replace(" + ", u" × "), datetime_to_epochms(server_now),))
            except:
                print("Exception while processing %s" % (s,))
                raise

    cursor.execute("commit")

print("queried %d times" % br.query_count)

urllib.urlopen("http://dms.chad.org/reset/2192101799958074132").read()

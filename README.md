# lynx-info
Connect Lynx' info to riders and observers

Web pages, typically visited in this order:

* [detect.html](http://bus.chad.org/detect), to get location and direct people to a page for the nearest stop, and redirect to stop info page.
* [stop.html](http://bus.chad.org/here?7004) (e.g), to show a stop's intersecting bus routes, and other stops nearby.
* [map.html](http://bus.chad.org/map), a map view of the routes and predicted stop times. This is almost better than [Lynx' own map](http://lynxbustracker.com/bustime/map/displaymap.jsp), but may not be sustainable.

There are a few php files, and these are the terrible compromise to get some smarts on the server Chad has provisioned somewhere.

There's some python that does the work of maintaining a copy of Lynx' data. It's expensive to query, and Lynx has a rate limit of 1e5 queries a day, which is okay for a few hundred stops, but not for the other 90% of Lynx that isn't online yet. 

Chad says: It should be possible to watch route endpoints and sentinel stations along the network and use changes in predictions to know whether we need to re-ask for stop predictions. If the end doesn't have a change in predictions, we don't need to ask for updates for stops along that line. Some simple graph-informed query-job queue shouldn't be too hard to design.

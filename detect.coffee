
all_stops = new Array
$.getJSON 'stops.json', (stops) ->
	console.log stops
	for stop_id, stop_info of stops
		all_stops[stop_id] = stop_info

	console.log all_stops

	navigator.geolocation.getCurrentPosition ((location) ->
		lat = location.coords.latitude
		lng = location.coords.longitude
		closest = null
		closest_distance = 1000000000
		for stop_id, stop of all_stops
			console.log 
			# Mr A. Square: "'Sup, Pythogoras?"
			dist = Math.sqrt (Math.pow lat-stop["latitude"], 2) + (Math.pow lng-stop["longitude"], 2)
			if dist < closest_distance
				closest_distance = dist
				closest = stop_id

		window.location = "/here?" + closest
	), () ->
		window.location = "/map"

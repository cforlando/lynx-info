root = exports ? this

marker_date_formatter = new Intl.DateTimeFormat "latn", { hour: "numeric", minute: "2-digit", "12-hour": true, }

root.routes_by_routeid = new Array
root.markers_by_stopid = new Array
root.route
root.current_infowindows = new Array

root.page_load = Date.now()

window.initialize_markers = (map) ->

	strptime = (str) ->
		d = new Date
		parts = null
		if str.match
			parts = str.match /(\d\d\d\d)(\d\d)(\d\d) (\d\d):(\d\d):?(\d*)/
		if not parts
			console.error "Incoming string #{ str } is unparsable"
			return undefined
		d.setYear parts[1]
		d.setMonth parts[2]
		d.setDate parts[3]
		d.setHours parts[4]
		d.setMinutes parts[5]
		d.setSeconds (parts[6] or 0)
		return d

	#bs = window.location.hostname.toLowerCase().replace /^(web.|www.)?/, "web."
	#x = (ch for ch, i in api_key when ch != bs[i]).join ""
	#url = "http://lynxbustracker.com/bustime/api/v2/gettime?k#{ bs[1] }y=#{ x }&format=json"
	#
	#prox url, (doc) ->
	#	console.info "server/local time calibration retrieved"
	#	now_ms = Date.now()
	#	server_now = strptime doc["bustime-response"]["tm"]
	#	server_to_local_delta = now_ms - server_now.getTime()
	#
	#	do (server_to_local_delta) ->
	#		root.server_strptime_to_local_time = (str) ->
	#			d = strptime str
	#			d.setTime d.getTime() + server_to_local_delta
	#			return d

	root.server_strptime_to_local_time = (str) ->
		d = strptime str
		#d.setTime d.getTime() + server_to_local_delta
		return d


	$.getJSON 'routes.json', (routes) ->
		for route_id, route_info of routes
			for pattern in route_info["direction-patterns"]
			
				flightPath = new google.maps.Polyline {
					path: ({lat: p["latitude"], lng: p["longitude"]} for p in pattern["points"]),
					geodesic: true,
					strokeColor: route_info["color"],
					strokeOpacity: 0.5,
					strokeWeight: 2
				}

				flightPath.setMap map
			routes_by_routeid[route_id] = { "name": route_info["human-name"], "direction-stops": route_info["direction-stops"], "color": route_info["color"] }

	$.getJSON 'stops.json', (stops) ->
		for stop_id, stop_info of stops
			marker = new google.maps.Marker {
				position: { lat: stop_info["latitude"], lng: stop_info["longitude"] },
				map: map,
				title: stop_info["human_name"],
				visible: true
			}

			stop_name = stop_info["human_name"]

			do (marker) ->
				markers_by_stopid[stop_id] = marker

				marker.setIcon 'pins/no-info.png'
				marker.addListener 'click', () ->
					if ! marker.chad_stop_name 
						return

					div = document.createElement "DIV"

					p = document.createElement "P"
					p.appendChild document.createTextNode marker.chad_stop_name 
					div.appendChild p

					if marker.chad_predictions
						ul = document.createElement "ul"
						lines = new Array

						for prediction in marker.chad_predictions
							route_id = prediction["route_id"]
							direction = prediction["direction"]
							if not lines[route_id]
								lines[route_id] = new Array
							if not lines[route_id][direction]
								lines[route_id][direction] = new Array
							lines[route_id][direction].push prediction

						for route_id, predictions_for_direction of lines
							route_info = routes_by_routeid[route_id]
							for direction, predictions of predictions_for_direction
								li = document.createElement "li"
								li.setAttribute "style", "border-color: #{ route_info['color'] };"

								span = document.createElement "span"
								span.setAttribute "style", "border-color: #{ route_info['color'] };"
								span.setAttribute "class", "route-id"
								span.appendChild document.createTextNode route_info['name']
								li.appendChild span

								span = document.createElement "span"
								span.setAttribute "class", "route-direction"
								span.appendChild document.createTextNode direction
								li.appendChild span

								for prediction in predictions
									console.log prediction
									span = document.createElement "span"
									span.setAttribute "class", "route-direction-arrival-time #{ if prediction['is_delayed'] then 'route-direction-arrival-time-delayed' else 'route-direction-arrival-time-ontime' }"
									span.appendChild document.createTextNode marker_date_formatter.format prediction['predicted_time_utcms']
									li.appendChild span
							
							ul.appendChild li
						
						div.appendChild ul
					else
						p = document.createElement "P"
						p.setAttribute "title", marker.chad_cache_stale_at
						if marker.chad_prediction_error_message 
							p.appendChild document.createTextNode marker.chad_prediction_error_message 
						else
							p.appendChild document.createTextNode "There is no reported real-time information about this stop yet."
						div.appendChild p

					infowindow = new google.maps.InfoWindow { content: div }
					for old_iw in current_infowindows
						old_iw.close()
					current_infowindows.push infowindow
					infowindow.open map, marker

				marker.chad_predictions = new Array
				marker.chad_want_next_update = 1
				marker.chad_processing = false
				marker.chad_last_update = 0
				marker.chad_stop_id = stop_info["stop_id"]
				marker.chad_stop_name = "#{ stop_name }"


	scan_all = () ->
		now_ms = Date.now()

		stops_want_update = new Array
		for stop_id, marker of markers_by_stopid

			root.manage_marker stop_id, marker, now_ms

			if marker.chad_want_next_update
				if marker.chad_want_next_update < now_ms
					stops_want_update.push stop_id
				#else
				#	console.debug "Ignoring #{ stop_id }, with plan to get it only after waiting #{ (marker.chad_want_next_update - now_ms) / 1000 } sec"
			else if marker.chad_last_update < (now_ms - 180000)
				stops_want_update.push stop_id
			else
				console.debug "Ignoring stop #{ stop_id } because #{ marker.chad_want_next_update } is falsey and last update is too recent"

		if stops_want_update.length != 0
			update_stops stops_want_update

	scan_all()
	window.setInterval scan_all, 10000


update_stops = (stops_out_of_date) ->
	stops_need_processing = new Array
	for s in stops_out_of_date
		if not markers_by_stopid[s].chad_processing
			stops_need_processing.push s

	if stops_out_of_date.length != stops_need_processing.length
		console.debug "Out of #{ stops_out_of_date.length }, we excluded all but #{ stops_need_processing.length } because they have processors working on them"

	if stops_need_processing.length == 0
		console.warn "Nothing to update"
		console.warn "This could be a problem if #{ stops_out_of_date } is not empty"
		return

	for block_starting in [0..stops_need_processing.length] by 50

		stop_id_list = stops_need_processing[block_starting...(block_starting+50)]

		if stop_id_list.length == 0
			console.warn "Nothing to update"
			console.warn "This could be a problem if #{ stops_out_of_date } is not empty"
			continue

		url = "predict?stops=#{ stop_id_list.join ',' }"

		do (url, stop_id_list) ->

			# claim these for processing
			for stop_id in stop_id_list
				markers_by_stopid[stop_id].chad_processing = true

			$.getJSON url, (doc) ->
				try
					now_ms = Date.now()
					recency_ms = doc["freshness_ms"]

					error = document.getElementById "error"
					if ((now_ms - recency_ms) > 720000)
						error.style.display = "inline"
						if recency_ms
							error.innerHTML = "This information is #{ (now_ms - recency_ms) // 60000 } min stale. Sorry!";
						else
							error.innerHTML = "This information is stale. Sorry!";
					else
						error.style.display = "none"

					new_predictions = new Array  # prepare for two-passes

					#if "error" of doc["bustime-response"]
					#	for error_info in doc["bustime-response"]["error"]
					#		stop_id = error_info["stpid"]
					#		marker = markers_by_stopid[stop_id]
					#		# could we have error and also predictions? Set default. Let predictions override.
					#		marker.chad_prediction_error_message = error_info["msg"]

					for prediction in doc["predictions"]  # first, gather all predictions, grouping by stop

						stop_id = prediction["stop_id"]
						if not new_predictions[stop_id]
							new_predictions[stop_id] = new Array
						new_predictions[stop_id].push prediction
						
					for stop_id, predictions of new_predictions  # second, process all predictions by stop
						marker = markers_by_stopid[stop_id]

						if predictions.length == 0
							sec_delay = 3600
						else
							predictions.sort (left, right) ->
								left["predicted_time_utcms"] > right["predicted_time_utcms"]

							t = predictions[0]["predicted_time_utcms"]
							for pred in predictions
								if pred["predicted_time_utcms"] > now_ms
									t = pred["predicted_time_utcms"]
									break
									# use the first time that's in the future

							# ramp up polling when the bus is close
							until_then_sec = (t - now_ms) / 1000
							if until_then_sec < 240
								sec_delay = 30
							else if until_then_sec < 600
								sec_delay = 90
							else if until_then_sec < 900
								sec_delay = 300
							else
								sec_delay = 600

							marker.chad_cache_stale_at = predictions[0]["cache_update_scheduled_at"]

						marker.chad_want_next_update = now_ms + (sec_delay * 1000)
						marker.chad_last_update = Date.now()
						marker.chad_predictions = (p for p in predictions when p["predicted_time_utcms"] > now_ms)

						root.manage_marker stop_id, marker, now_ms
				finally
					for stop_id in stop_id_list
						markers_by_stopid[stop_id].chad_processing = false


root.manage_marker = (stop_id, marker, now_ms) ->

	currently_visible = marker.getVisible()

	if marker.chad_predictions.length == 0
		#if currently_visible
		#	console.info "Changing to INVISIBLE, #{ marker.chad_stop_id }"
		#marker.setVisible false
		marker.setIcon 'pins/no-info.png'
		marker.setZIndex 0
	else

		t = marker.chad_predictions[0]
		for pred in marker.chad_predictions
			if pred["predicted_time_utcms"] > now_ms
				t = pred
				break
				# use the first time that's in the future

		if ! currently_visible
			console.info "Changing to   visible, #{ marker.chad_stop_id }"
			marker.setVisible true
		until_then_sec = (t["predicted_time_utcms"] - now_ms) / 1000
		m = (Math.floor(until_then_sec / 60))
		marker.setZIndex 800 - Math.max(m, 800)

		if until_then_sec < -1800
			#marker.setVisible false
			marker.setIcon 'pins/no-info.png'
			marker.setZIndex 2
		else if until_then_sec < -30
			marker.setIcon "pins/stale.png"
		else if until_then_sec < 30
			marker.setIcon "pins/past.png"
		else if until_then_sec < 90
			marker.setIcon "pins/#{ m }.png"
		else if until_then_sec < 180
			marker.setIcon "pins/#{ m }.png"
		else if until_then_sec < 300
			marker.setIcon "pins/#{ m }.png"
		else if until_then_sec < 600
			marker.setIcon "pins/#{ m }.png"
		else if until_then_sec < 900
			marker.setIcon "pins/medium.png"
		else
			marker.setIcon "pins/far.png"

if (! started && map)
	started = true;
	initialize_markers(map);

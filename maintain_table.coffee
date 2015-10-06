root = exports ? this

target_stop_info = null
target_stop_id = window.location.search.substring 1

date_formatter = new Intl.DateTimeFormat "latn", { hour: "numeric", minute: "2-digit", "12-hour": true, }

routes_by_routeid = new Array
$.getJSON 'routes.json', (routes) ->
	for route_id, route_info of routes
		routes_by_routeid[route_id] = { "name": $.trim(route_info["human-name"]), "direction-stops": route_info["direction-stops"], "color": route_info["color"], }

	target_stop_info = null
	all_stops = new Array
	$.getJSON 'stops.json', (stops) ->
		for stop_id, stop_info of stops
			all_stops[stop_id] = stop_info
			if target_stop_id == stop_id
				target_stop_info = stop_info

		if target_stop_info
			[latitude, longitude] = [target_stop_info["latitude"], target_stop_info["longitude"]]

			distance_to_here = (other_name) ->
				other = stops[other_name]
				return Math.sqrt (Math.pow latitude-other["latitude"], 2) + (Math.pow longitude-other["longitude"], 2)

			comparator = (left, right) ->
				return (distance_to_here left) - (distance_to_here right)

			stops_sorted_names = (k for k, v of all_stops)
			stops_sorted_names.sort(comparator)


			title_container = document.getElementById "stop-title"
			info_container = document.getElementById "stop-info"
			neighbor_container = document.getElementById "stop-neighbors"
			near_neighbor_container = document.getElementById "near-neighbors"
			iframe_container = document.getElementById "frame"

			# populate title
			title_container.appendChild document.createTextNode target_stop_info["human_name"]
			
			# populate neighbors
			for routes_interacting in target_stop_info["routes_interacting"]
				[route_id, direction] = routes_interacting

				tr = document.createElement "TR"
				tr.setAttribute "style", "border-color: #{ routes_by_routeid[route_id]['color'] };"

				[prev, current, post] = [null, null, null]
				for stop in routes_by_routeid[route_id]["direction-stops"][direction]
					[prev, current, post] = [current, post, stop]

					if current == target_stop_id

						th = document.createElement "TH"
						span = document.createElement "SPAN"
						span.appendChild document.createTextNode "#{ routes_by_routeid[route_id]['name']}"
						th.appendChild span
						tr.appendChild th

						td = document.createElement "TD"
						tdarr = document.createElement "TD"
						if prev
							a = document.createElement "A"
							a.setAttribute "href", "?" + prev
							a.appendChild document.createTextNode "(away from #{ direction.toLowerCase() })"
							a.appendChild document.createElement "br"
							a.appendChild document.createTextNode all_stops[prev]["human_name"]
							td.appendChild a

							tdarr.appendChild document.createTextNode "→"

						tr.appendChild td
						tr.appendChild tdarr

						td = document.createElement "TD"
						td.appendChild document.createTextNode all_stops[current]["human_name"]
						tr.appendChild td

						td = document.createElement "TD"
						tdarr = document.createElement "TD"
						if post
							a = document.createElement "A"
							a.setAttribute "href", "?" + post
							tdarr.appendChild document.createTextNode "→"

							a.appendChild document.createTextNode " "
							a.appendChild document.createTextNode all_stops[post]["human_name"]
							a.appendChild document.createElement "br"
							a.appendChild document.createTextNode "(toward #{ direction.toLowerCase() })"
							td.appendChild a

						tr.appendChild tdarr
						tr.appendChild td
				neighbor_container.appendChild tr

			# populate near list
			for near_name in stops_sorted_names[1..5]

				li = document.createElement "LI"
				a = document.createElement "A"
				a.setAttribute "href", "?" + near_name
				a.appendChild document.createTextNode all_stops[near_name]["human_name"]
				li.appendChild a
				li.appendChild document.createTextNode ", "

				for ri in all_stops[near_name]["routes_interacting"]
					[route_id, direction] = ri
					span = document.createElement "SPAN"
					span.setAttribute "class", "route-cell"
					span.setAttribute "style", "border-color: #{ routes_by_routeid[route_id]['color'] };"
					span.appendChild document.createTextNode "#{ routes_by_routeid[route_id]['name'] } #{ direction.toLowerCase() }"
					li.appendChild span

				near_neighbor_container.appendChild li
			
			if frame_container
				iframe = document.createElement "IFRAME"
				iframe.setAttribute "width", "515"
				iframe.setAttribute "noscroll", "noscroll"
				iframe.setAttribute "src", "http://lynxbustracker.com/bustime/eta/eta.jsp?id=#{ target_stop_id }&showAllBusses=on"
				do (iframe) ->
					window.setInterval (() ->
						iframe.setAttribute "src", "http://lynxbustracker.com/bustime/eta/eta.jsp?id=#{ target_stop_id }&showAllBusses=on&junk=" + Date.now()
					), 10000

			if info_container
				do (target_stop_id, routes_by_routeid, info_container) ->
					url = "predict?stops=#{ target_stop_id }"
					update_stop = () ->
						url = "predict?stops=#{ target_stop_id }"
						$.getJSON url, (doc) ->
							now_ms = Date.now()
							recency_ms = doc["freshness_ms"]

							error = document.getElementById "error"
							if ((now_ms - recency_ms) > 720000)
								error.style.display = "inline"
								if recenty_ms
									error.innerHTML = "This information is #{ (now_ms - recency_ms) // 60000 } min stale. Sorry!";
								else
									error.innerHTML = "This information is stale. Sorry!";
							else
								error.style.display = "none"

							new_predictions = new Array  # prepare for two-passes
							for prediction in doc["predictions"]  # first, gather all predictions, grouping by stop

								route_id = prediction["route_id"]
								route_info = routes_by_routeid[route_id]
								if not route_info
									console.log route_id
								direction = prediction["direction"]

								li = document.createElement "LI"
								li.setAttribute "style", "border-color: #{ route_info['color'] };"

								time = document.createElement "TIME"
								time.appendChild document.createTextNode date_formatter.format prediction['predicted_time_utcms']
								time.setAttribute "class", "#{ if prediction['is_delayed'] then 'delayed' else 'ontime' }"
								li.appendChild time

								li.appendChild document.createTextNode route_info['name']
								li.appendChild document.createTextNode " "
								li.appendChild document.createTextNode direction
							
								new_predictions.push li

							while info_container.hasChildNodes()
								info_container.removeChild info_container.lastChild

							for child in new_predictions
								info_container.appendChild child

					update_stop()
					window.setInterval update_stop, 10000

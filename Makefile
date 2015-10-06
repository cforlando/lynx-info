all: routes.json detect.js maintain_table.js maintain_map.js jquery-2.1.4.min.js map.html
	rsync secret-key *.json *.php maintain_*.js detect.js screenshot.png jquery-2.1.4.min.js h.html detect.html here.html map.html bus:
	scp cron.py bus:/home/protected
	ssh bus mkdir -p pins
	rsync pins/* bus:pins/
	wget -q -O - http://bus.chad.org/cron.php

jquery-%.js:
	wget -nv http://code.jquery.com/jquery-2.1.4.min.js

routes.json:
	./precompute.py

%.js: %.coffee
	coffee -c $^

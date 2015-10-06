<?php 

error_reporting(E_ALL);

$stopsstring = "";
if (array_key_exists("stops", $_GET)) {
	$stopsstring = preg_replace("/[^,0-9a-zA-Z]/", "x", $_GET["stops"]);
	$stop_ids = "'" . implode("','", explode(',', $stopsstring)) . "'";
}


$db = new SQLite3('/home/protected/web-owned/lynx-proxy.sqlite3');


$result = $db->query('SELECT max(insert_time_ms) FROM predictions');
$dbrow = $result->fetchArray(SQLITE3_NUM);
$most_recent = (int) $dbrow[0];

if ($stopsstring) {
	$result = $db->query("SELECT predictions.stop_id, predicted_time_ms, is_delayed, direction, route_id, destination, cache_sched.due FROM predictions left join cache_sched on (predictions.stop_id=cache_sched.stop_id) WHERE predictions.stop_id in ($stop_ids)");
} else {
	$result = $db->query('SELECT predictions.stop_id, predicted_time_ms, is_delayed, direction, route_id, destination, cache_sched.due FROM predictions left join cache_sched on (predictions.stop_id=cache_sched.stop_id) ORDER BY predicted_time_ms ASC');
}

$predictions = array();
while (( $dbrow = $result->fetchArray(SQLITE3_ASSOC) )) {
	$r = array();
	$r['stop_id'] = $dbrow['stop_id'];
	if ($dbrow['predicted_time_ms']) {
		$r['predicted_time_utcms'] = (int) $dbrow['predicted_time_ms'];
	} else {
		$r['predicted_time_utcms'] = NULL;
	}
	$r['is_delayed'] = ($dbrow['is_delayed'] != 0);
	$r['direction'] = $dbrow['direction'];
	$r['route_id'] = $dbrow['route_id'];
	$r['destination'] = $dbrow['destination'];
	$r['cache_update_scheduled_at'] = $dbrow['due'];
	array_push($predictions, $r);
}

$data = array();

$data["predictions"] = $predictions;
$data["freshness_ms"] = $most_recent;

header('Content-type: application/json');

print(json_encode($data));

?>

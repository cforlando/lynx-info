<?php 

error_reporting(E_ALL);
header('Content-type: text/plain');

passthru("python2 /home/protected/cron.py 2>&1", $ret);

if ($ret != 0) {
	print "$ret\n";
}
?>

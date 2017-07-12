# icinga-plugins
Various icinga plugins I have written or modified


## check_mvetec.pl
If you hook a lantronix UDS1100 up to the RS-485 serial on one or more [MVE TEC 3000](http://files.chartindustries.com/TEC3000%20Tech%20Freezer%20Manual%2013289499%20F%203.pdf) cryo freezers, you can talk to it over TCP. This nagios plugin lets you check its values (mainly temperature probes) this way.

## check_thum.pl

This is just a simple wrapper to check the temperature on a Thum USB temperature probe

## rcell.pl

This is a script to use the [MultiTech rCell SMS Router](http://www.multitech.com/brands/multiconnect-rcell-100-series) with icinga. It can:
  * Check the Cell signal strength
  * Send an SMS for notifications

TODO Still:
  * Run as a daemon and constantly check if the rCell has recieved any text messages, pass them to a handler script.

#!/usr/bin/perl
#
# check_mvetec.pl
#
# MVE TEC 3000 Freezers have an 'alarm' relay to make it easy to plug into a remote notification
# system, but what if you want more detail? Which freezer in the group is upset and why?
# Turns out, they also have a little brain which speaks RS-485 4 wire serial and can be
# queried for data such as temperature probe values.
#
# Hardware Setup:
#   In the menu, under advanced, set the MODBUS id uniquely for each freezer on the bus (RS-485 lets
#   you wire them all together)
#   Instead of the USB dongle that comes with Chart's software ($500!) get a Lantronix UDS1100
#   RS-485 to ethernet adapter (only around $200). You'll need a 25 pin to RJ45 adapter, and
#   reference the wiring on page 92 of the MVE TEC manual and the 4 wire RS485 diagram that
#   comes with the UDS1100 for proper wire mapping.  (rx+ to tx+, rx- to tx-)
#   Once the UDS1100 is configured, you can connect to it with telnet and send it things like:
#     001 TEMPA?
#   It will respond with the value. Commands are well documented in the MVE TEC manual.
#     -197.10
#
#   This script is an icinga plugin which uses the above setup to allow you to monitor
#   values on your freezer from icinga or nagios. It can also optionally log the results
#   to ganglia, which we like as a nice graphic record.
#
use strict;
use warnings;

use Nagios::Plugin;
use FindBin qw($RealBin);
use Proc::PID::File;

my $waitcount = 0;



my $GMETRIC = "/usr/bin/gmetric";

my $np = Nagios::Plugin->new( 
         shortname => "mvetec",
         usage => "Usage: %s [-c|--critical=<threshold> ] [ -w|--warning=threshold> ]",
);

$np->add_arg( 
      spec => 'warning|w=s',
      help => '-w, --warning=INTEGER:INTEGER',
);
$np->add_arg( 
      spec => 'critical|c=s',
      help => '-c, --critical=INTEGER:INTEGER',
);

$np->add_arg(
      spec => 'host|H=s',
      help => '-H, --host=hostname',
);

$np->add_arg(
      spec => 'port|p=i',
      help => '-p, --port (default is 10001)',
);

$np->add_arg(
      spec => 'query|q=s',
      help => '-q, --query  (example: "002 TEMPA" where 002 is the modbus ID and TEMPA is temperature probe A)',
);


$np->add_arg( 
      spec => 'ganglia|g',
      help => '-g, --ganglia',
);


$np->getopts;

my $host = $np->opts->host;
die("--host required") unless $host;

my $port = $np->opts->port;
$port = 10001 unless $port;

my $query = $np->opts->query;
die("--query required") unless $query;

my $modbus_id;
my $modbus_var;

#print "DEBUG: Sending $host:$port, $modbus_id $query?\n";
if($query =~ /^(\d{3,3}) ([A-Za-z0-9_-]+)/) {
   $modbus_id = $1;
   $modbus_var = $2;
}
else {
   $np->nagios_exit( UNKNOWN, "--query '$query' does not contain a valid query: format: xxx yyyy where x are modbus id and y are variable to query"); 
}

my $warning_threshold = $np->opts->warning;
my $critical_threshold = $np->opts->critical;

# Check we arent running twice at once
while(Proc::PID::File->running( dir => '/tmp' )) {
   if($waitcount++ > 90) {
      $np->nagios_exit( UNKNOWN, "Lockfile in /tmp exists. Tried waiting for it but we never got a chance to run.");
   }
   sleep 1;
}         

my $sendstr = "$modbus_id $modbus_var?";
my $result = `echo "$sendstr" | /bin/nc.openbsd -C -q 1 -w 3 $host $port`;

#my $result = `$THUMCTL -t -f`;

if($result =~ /(  [+-]? ( (\d+ (\.\d*)?)  |  (\.\d+) ))/x) {
   my $value = $1;
   #print "DEBUG: $value\n";
   my $code = $np->check_threshold(
      check => $value,
      warning => $warning_threshold,
      critical => $critical_threshold,
   );
   if($np->opts->ganglia) {
      my $name = "lnfreezer_". $modbus_id . "_". $modbus_var;
      #print "DEBUG: $GMETRIC -g scada -n \"$name\" -v \"$value\" -t double -u \"C\" -x 300\n";
      system("$GMETRIC -g scada -n \"$name\" -v \"$value\" -t double -u \"C\" -x 300\n");
   }
   $np->nagios_exit( $code, $value);
}
else {
   $np->nagios_exit( UNKNOWN, "Could not understand return data: '$result'");
}

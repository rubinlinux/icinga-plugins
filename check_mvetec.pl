#!/usr/bin/perl
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

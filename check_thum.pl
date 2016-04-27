#!/usr/bin/perl
#
use strict;
use warnings;

use Nagios::Plugin;
use FindBin qw($RealBin);


my $THUMCTL = "$RealBin/thumctl";
my $GMETRIC = "/usr/bin/gmetric";

my $np = Nagios::Plugin->new( 
         shortname => "thum",
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
      spec => 'ganglia|g',
      help => '-g, --ganglia',
);


$np->getopts;

my $result = `$THUMCTL -t -f`;
chomp $result;

my $warning_threshold = $np->opts->warning;
my $critical_threshold = $np->opts->critical;

if($result =~ /^.* .* (\d*\.?\d+) F/) {
   my $value = $1;
   my $code = $np->check_threshold(
         check => $value,
         warning => $warning_threshold,
         critical => $critical_threshold,
   );
   if($np->opts->ganglia) {
      #print $value;
      system("$GMETRIC -g it -n \"Server Room Temp\" -v \"$value\" -t double -u \"F\" -x 300\n");
      exit;
   }
   else {
      $np->nagios_exit( $code, $value);
   }
}
else {
   $np->nagios_exit( UNKNOWN, "Could not understand return data: '$result'");
}


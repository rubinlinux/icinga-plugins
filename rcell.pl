#!/usr/bin/perl -w
# nagios: -epn
#
# COPYRIGHT:
#  
# This software is Copyright (c):
#
#   * 2009 NETWAYS GmbH, Birger Schmidt <info@netways.de>
#   * 2017 ZIRC, Alex Schumann <alex@zebrafish.org>
# 
# LICENSE:
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from http://www.fsf.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.fsf.org.
# 

#This util is based on the API Documentation located at:
#http://www.multitech.com/documents/publications/manuals/s000576_1_2_1.pdf
#and examples at:
#http://www.multitech.net/developer/software/mtr-api-reference/rcell_api_requests/making-requests/send_sms/
#


######################################################################
######################################################################
#
# configure here to match your system setup
#
my $object_cache	= "/var/spool/nagios/objects.cache";
my $nagios_cmd		= "/var/spool/nagios/rw/nagios.cmd";
my $logfile			= "/usr/local/var/nagios/rcell.log";

my $ok = "^OK ";
my $ack = "^ACK ";

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case bundling);
use File::Basename;

use Mojo::UserAgent;

use Data::Dumper;
use Pod::Usage;

#our @state = ('OK', 'WARNING', 'CRITICAL', 'UNKNOWN');

my $HowIwasCalled			= "$0 @ARGV";

# version string
my $version					= '1.0';

my $basename = basename($0);

# init command-line parameters
my $hostaddress				= undef;
my $timeout					= 60;
my $warning					= undef; 
my $critical				= undef;
my $show_version			= undef;
my $verbose					= undef;
my $help					= undef;
my $user					= undef;
my $pass					= undef;
my $number					= undef;
my $noma					= 0;
my $message					= undef; #'no text message given';
my $contactgroup				= undef;

my $send                    = 0;
my $check                   = 0;

my @msg						= ();
my @perfdata				= ();
my $exitVal					= undef;
my $loginID					= '0';
my $do_not_verify			= 0;


#TODO: Are these still relevant?
my %smsErrorCodes = (
#Error Code, Error Description
400 => 'Bad Request',
401 => 'Unauthorized',
403 => 'Forbidden',
404 => 'Not Found',
405 => 'Method Not Allowed',
406 => 'Not Acceptable',
408 => 'Request Timeout',
409 => 'Conflict',
500 => 'Internal Server Error',
501 => 'Not Implimented'
);

sub mypod2usage{
    # Load Pod::Usage only if needed.
  #  require "Pod/Usage.pm";

    #print "DEBUG: mypod2usage\n";
    #print Dumper(@_);
	#pod2usage(@_);
    #pod2usage({-verbose => 1, -msg => "\nERROR: Testing\n", -exitval => 1});
    pod2usage(@_);
}

# get command-line parameters
GetOptions(
   "H|hostaddress=s"		=> \$hostaddress,
   "v|verbose"				=> \$verbose,
   "V|version"				=> \$show_version,
   "h|help"					=> \$help,
   "u|user=s"				=> \$user,
   "p|password=s"			=> \$pass,
   "n|number=s"				=> \$number,
#   "noma"					=> \$noma,
#   "o|objectcache=s"		=> \$object_cache,
   "m|message=s"			=> \$message,
   "w|warning=i"			=> \$warning,
   "c|critical=i"			=> \$critical,
#   "g|contactgroup=s"			=> \$contactgroup,
) or mypod2usage({
	-msg     => "\n" . 'Invalid argument!' . "\n",
	-verbose => 1,
	-exitval => 3
});

sub printResultAndExit {

	# print check result and exit

	my $exitVal = shift;

	print "@_" if (@_);

	print "\n";

	# stop timeout
	alarm(0);

	exit($exitVal);
}

if ($show_version) { printResultAndExit (0, $basename . ' - version: ' . $version); }

mypod2usage({
	-verbose	=> 1,
	-exitval	=> 3
}) if ($help);



# set timeout
local $SIG{ALRM} = sub {
	if (defined $exitVal) {
		print 'TIMEOUT: ' . join(' - ', @msg) . "\n";
		exit($exitVal);
	} else {
		print 'CRITICAL: Timeout - ' . join(' - ', @msg) . "\n";
		exit(2);
	}
};

alarm($timeout);


sub urlencode {
	my $str = "@_";
	$str =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	return $str;
}

sub urldecode {
	my $str = "@_";
	$str =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
	return $str;
}

sub prettydate { 
# usage: $string = prettydate( [$time_t] ); 
# omit parameter for current time/date 
   @_ = localtime(shift || time); 
   return(sprintf("%04d/%02d/%02d %02d:%02d:%02d", $_[5]+1900, $_[4]+1, $_[3], @_[2,1,0])); 
} 

sub justASCII {
	join("",
		map { # german umlauts
			chr($_) eq 'ö' ? 'oe' :
			chr($_) eq 'ä' ? 'ae' :
			chr($_) eq 'ü' ? 'ue' :
			chr($_) eq 'Ö' ? 'Oe' :
			chr($_) eq 'Ä' ? 'Ae' :
			chr($_) eq 'Ü' ? 'Ue' :
			chr($_) eq 'ß' ? 'ss' :
			$_ > 128 ? '' :						# cut out anything not 7-bit ASCII
			chr($_) =~ /[[:cntrl:]]/ ? '' :		# and control characters too
			chr($_)								# just the ASCII as themselves
	} unpack("U*", $_[0]));						# unpack Unicode characters
}  

# Make sure input string is nothing weird, just a 10 digit american phone number with an optional 1 in front (which will be removed)
sub phoneNumber {
    my $str = shift;
    $str =~ s/[^0-9]//g;
    $str =~ /1?(\d){10}/;
    $number = $1;
    #TODO: Prevent some malicious area codes?
    return $number;
}

sub rest_login {
    my $ua = shift;
    my $url = shift;
    my $username = urlencode(shift);
    my $password = urlencode(shift);
    #Fresh user agent
    my $result = $ua->get("$url/api/login?username=$username&password=$password")->res;
    my $status = $result->json('/status');
    my $token = $result->json('/result/token');
    if($status eq 'success' && $token) {
        return $token;
    }
    else {
        printResultAndExit(5, "ERROR: Unable to log in to $url");
    }
}

sub rest_logout {
    my $ua = shift;
    my $url = shift;
    my $token = shift;
    $ua->get("$url/api/logout?token=$token")->res->body();
}

sub rest_sendSMS {
    my $ua = shift;
    my $url = shift;
    my $token = shift;
    my $to = phoneNumber(shift);
    my $msg = urlencode(justASCII(shift));
    my $request = "$url/api/sms/outbox?data={\"recipients\": [\"$to\"], \"message\": \"$msg\"}&token=$token&method=POST";
    print "DEBUG: Sending an SMS: $request\n";
    my $result = $ua->post($request)->res;
    if($result->json('/status') eq 'success') {
        return 0;
    } 
    else {
        printResultAndExit(1, "Unable to send: " . $result->json('/error'));
    }
}

sub rest_getRadioStatus {
    my $ua = shift;
    my $url = shift;
    my $token = shift;
    my $request = "$url/api/stats/radio?token=$token&method=GET";
    my $result = $ua->get("$request")->res;
    my $status = $result->json('/result');
    return $status;
}

sub sendSMS {
   my $number = shift;
   my $message = shift;

   #print "DEBUG: Sending an sms to $number\n";
   my $ua = Mojo::UserAgent->new;
   my $url = "http://$hostaddress";
   #print "DEBUG: $user / $pass\n";
   my $token = rest_login($ua, $url, $user, $pass);
   if($token) {
       #print "DEBUG: Got a token from login: $token\n";
       rest_sendSMS($ua, $url, $token, $number, $message);
       rest_logout($ua, $url, $token);
   }
}

sub getSignal {
   my $ua = Mojo::UserAgent->new;
   my $url = "http://$hostaddress";

   #print "DEBUG: $user / $pass\n";
   my $token = rest_login($ua, $url, $user, $pass);
   my $status;
   if($token) {
       #print "DEBUG: Got a token from login: $token\n";
       $status = rest_getRadioStatus($ua, $url, $token);
       rest_logout($ua, $url, $token);
   }
   return $status;
}

# ######################################
# Begin


if ($message) {
	open (LOG, ">>".$logfile) or *LOG = *STDERR;
	print LOG prettydate(); 
	print LOG " SMSsend: $HowIwasCalled\n"; 
	close LOG;

    unless ($hostaddress) { 
        printResultAndExit(2, "ERROR: hostaddress missing!");
    }
    unless ($user) { 
        printResultAndExit(2, "ERROR: username missing!");
    }
    unless ($pass) { 
        printResultAndExit(2, "ERROR: password missing!");
    }

	unless ($number) { 
        printResultAndExit(2, "ERROR: number missing!");
	}
	#my $msg = urlencode("@_");
	#$message =~ tr/\0-\xff//UC;		# unicode to latin-1

	if ($verbose) { 
        print 'Sending to   : ' . $number . "\n";
        print 'Message      : ' . $message . "\n"; 
    }
    sendSMS($number, $message);

    open (LOG, ">>".$logfile) or *LOG = *STDERR;
    print LOG prettydate(); 
    print LOG " SMSsend: $number - " . $message . "\n"; 
    close LOG;
	printResultAndExit ($exitVal, $message); 
}
elsif ($warning || $critical) {
    unless ($hostaddress) { 
        printResultAndExit(2, "ERROR: hostaddress missing!");
    }
    unless ($user) { 
        printResultAndExit(2, "ERROR: username missing!");
    }
    unless ($pass) { 
        printResultAndExit(2, "ERROR: password missing!");
    }

    mypod2usage({
        -msg	    => "\n" . 'Warning level is lower than critical level. Please check.' . "\n",
        -verbose	=> 1,
        -exitval	=> 3
    }) if ($warning < $critical);
	
    my $status = getSignal();

    my $signal = $status->{'rssi'};
    #print "DEBUG: Signal from device is $signal\n";

    if($signal < $critical) {
        printResultAndExit (2, "CRITICAL: $hostaddress rcell Signal Strength $signal is less than $critical"); 
    }
    elsif($signal < $warning) {
        printResultAndExit (1, "WARNING: $hostaddress rcell Signal Strength $signal is less than $warning"); 
    }
    #Get sysinfo
    #printResultAndExit (2, "CRITICAL: $hostaddress SMSFinder returned bad response. \n" . "Not yet implimented"); 
}

else {
	mypod2usage({
		-verbose	=> 1,
		-exitval	=> 3
	});
}


# DOCUMENTATION

=head1 NAME

=over 1

=item B<rcell.pl>

	the Nagios Signal check plugin and SMS message Sender for the Multitech rCell

=back

=head1 DESCRIPTION

=over 1

=item Depending on how it is called,

	- Checks a Multitech rCell and returns if it is connected 
		to the GSM Network and the level of signal strength.
	- send an SMS via a Multitech rCell

=back

=head1 SYNOPSIS

=over 1

=item B<rcell.pl> 
    -H <hostname> -u <username> -p <password> -n <phonenumber> -m "<message>"

=item B<rcell.pl> 
    -H <hostname> -u <username> -p <password> -w <warninglevel> -c <criticallevel>

    [-H|--hostaddress=<hostaddress>]
    [-u|--user=<user>]
    [-p|--password=<password>]
    [-m|--message=<message text>]
    [-v|--verbose]
    [-h|--help] 
    [-V|--version]
    [-n|--number=<telephone number of the recipient>]
    [-w|--warning=<signallevel>]
    [-c|--critical=<signallevel>]

=back

=head1 OPTIONS

=over 4

=item -H <hostaddress>

Hostaddress of the SMSFinder

=item -v|--verbose

Enable verbose mode and show whats going on.

=item -V|--version

Print version an exit.

=item -h|--help

Print help message and exit.

=item -n|--number

Telephone number of the SMS recipient

=item -m|--message

SMS message text

=item -w|--warning

Warning level for signal strength. Scale is 0-30

=item -c|--critical

Critical level for signal strength. Scale is 0-30

=back

=head1 EXAMPLE for Nagios check configuration 

 # command definition to check SMSFinder via HTTP
 define command {
	command_name		check_smsfinder
	command_line		$USER1$/rcell.pl -H $HOSTADDRESS$ -u $USER15$ -p $USER16$ -w $ARG1$ -c $ARG2$
 }

 # service definition to check the SMSFinder
 define service {
	use					generic-service
	host_name			smsfinder
	service_description	smsfinder
	check_command		check_smsfinder!15!20	 # warning and critical in percent
	## maybe it's whise to alter the service/host template
	#contact_groups		smsfinders
  }
 
=head1 EXAMPLE for Nagios notification configuration 

 define command {
	command_name    notify-host-by-sms
	command_line    /usr/local/nagios/rcell.pl -H $HOSTADDRESS:rcell$ -u $USER13$ -p $USER14$ -n $CONTACTPAGER$ -m '$NOTIFICATIONTYPE$ $HOSTNAME$ is $HOSTSTATE$ /$SHORTDATETIME$/ $HOSTOUTPUT$'
 }

 define command {
	command_name    notify-service-by-sms
	command_line    /usr/local/nagios/smsack/sendsms.pl -H $HOSTADDRESS:rcell$ -u $USER13$ -p $USER14$ -n $CONTACTPAGER$ -m '$NOTIFICATIONTYPE$ $HOSTNAME$,$SERVICEDESC$ is $SERVICESTATE$ /$SHORTDATETIME$/ $SERVICEOUTPUT$'
 }

 # contact definition - maybe it's wise to alter the contact template
 define contact {
	contact_name                    smsfinder
	use                             generic-contact
	alias                           SMS Nagios Admin
	# send notifications via email and SMS
	service_notification_commands   notify-service-by-email,notify-service-by-sms
	host_notification_commands      notify-host-by-email,notify-host-by-sms
	email                           nagios@localhost
	pager                           +491725555555		# alter this please!
 }

 # contact definition - maybe it's wise to alter the contact template
 define contactgroup {
	contactgroup_name       rcell
	alias                   SMS Nagios Administrators
	members                 rcell
 }

=cut



# vim: ts=4 shiftwidth=4 softtabstop=4 
#backspace=indent,eol,start expandtab

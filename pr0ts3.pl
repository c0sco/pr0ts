#!/usr/bin/perl

## pr0ts3.pl
## Connect to every port on a machine to determine its state and report back via email.
## List ports that are closed but should be open and vice versa.
## 
##
## Matt Stofko 2003
## matt@mjslabs.com

use Mail::Mailer;
use Time::HiRes qw(ualarm);
use Socket;
use IPC::Shareable;
use strict;
use vars qw($child %ports);

##### CHANGE THIS STUFF #####
# Who to send email to when something is wrong
my $contact_address	= 	'matts@phjeer.us';
my $smtp_server		= 	'phjeer.us';
# IP to scan
my $ip					=	"184.105.237.83";
# Timeout value in microseconds. How long we wait for a port to respond before moving on.
# Up this for slow networks.
my $timeout			=	550;
# Ports that should be open
my %monitor			=	(
							22 => "open",
							25 => "open",
							80 => "open",
							111 => "open",
							443 => "open",
							995 => "open",
						);
#############################

$SIG{CHLD} = 'IGNORE';
tie %ports, 'IPC::Shareable', 'openports', {create => 1, destroy => 1};
$ports{'open'} = [];
$ports{'closed'} = [];
forkoff(1, 13000);
forkoff(13001, 26000);
forkoff(26001, 39000);
forkoff(39001, 52000);
forkoff(52001, 65535);

do { $child = wait() } until $child == -1;

if ($ports{'open'} || $ports{'closed'}) {
	my $msg = new Mail::Mailer 'smtp', Server => $smtp_server;
	$msg->open({To => $contact_address, Subject => 'Weird ports', From => 'pr0ts3'});
	if (scalar @{$ports{'open'}}) { # print ports that are open that should be closed
		print $msg "O: " .  join(" ", (sort {$a <=> $b} @{$ports{'open'}})), "\n";
	}
	if (scalar @{$ports{'closed'}}) { # print ports that are closed that should be open
		print $msg "C: " .  join(" ", (sort {$a <=> $b} @{$ports{'closed'}})), "\n";
	}
	$msg->close;
}


##### begin subs

sub forkoff {
	my $pid = fork();
	die "fork() failed: $!" unless defined $pid;
	return if $pid;
	checkports(shift, shift);
	exit;
}

sub checkports {
	my (%ports,$port,$p_addr);
	my ($from,$to) = @_;
	tie %ports, 'IPC::Shareable', 'openports';
	foreach $port ($from .. $to) {
		# Turn this on to see some status if you aren't running from cron 
		# print "checking $port\n" if !($port % 1000);
		eval {
			local $SIG{ALRM} = sub { die "timed out - $port\n"; };
			$p_addr = sockaddr_in($port, inet_aton $ip);
			socket(SH, PF_INET, SOCK_STREAM, getprotobyname('tcp'))
				or die "Error: Unable to open socket: $@";
			ualarm $timeout;
			if (connect(SH, $p_addr))
			{
				push(@{$ports{'open'}}, $port) if !(exists $monitor{$port}); # open but shouldn't be
			}
			ualarm 0;
			close(SH);
		};
		if ($@ =~ /^timed out - (\d+)$/) {
			push(@{$ports{'closed'}}, $1) if exists $monitor{$1}; # closed but shouldn't be
		}
	}
}

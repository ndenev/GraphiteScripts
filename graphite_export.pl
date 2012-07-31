#!/usr/bin/perl

# $Id: $

use strict;
use warnings;
use IO::Socket;

my $carbon_host = "graphite";
my $carbon_port = "2003";

my $socket;
my $ts;
my $hostname = `hostname -s`;
chomp($hostname);
my $oid;
my $val;
my $base = "$hostname.sysctl";
my @sysctl;
my $sctl;
my $sysctlret;
my $old = "";
my @data;
my $message;
my $sleep = 5;
my $idx;
sub carbon_connect;
my @sysctls = ("kstat.zfs", "vm.stats", "vm.pmap", "dev.ix", "dev.em", "dev.igb", "dev.bce");

carbon_connect;

while (1) {
	for ($idx = 0; $idx <= $#sysctls; $idx++) {
		@sysctl = `sysctl -e $sysctls[$idx] 2>/dev/null`;
		if ($? > 0) {
			print "Feteching sysctl($sysctls[$idx]) failed. Removing.\n";
			splice @sysctls, $idx, 1;
			$idx--;
			next;
		}
		foreach $sysctlret (@sysctl) {
			chomp($sysctlret);
			($oid, $val) = split('=', $sysctlret);
			$ts = time();
			$socket->send("$base.$oid $val $ts\n");
			if ( "$base.$sysctls[$idx]" ne $old) {
				print "Updating : $base.$sysctls[$idx]";
				$old = "$base.$sysctls[$idx]";
			}
		}
		print "\n";
	}
	print "Sleeping: $sleep secs\n";
	sleep $sleep;
}

$socket->shutdown(2);

sub carbon_connect {
	$socket = IO::Socket::INET->new (
		PeerAddr => $carbon_host,
		PeerPort => $carbon_port,
		Proto => 'tcp',
	);
	die "Unable to open socket: $!" unless ($socket);
}


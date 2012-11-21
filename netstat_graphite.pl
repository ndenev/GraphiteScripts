#!/usr/bin/perl

use IO::Socket;

my $carbon_host = "graphite";
my $carbon_port = "2003";

my $socket;

$nsre1  = qr/^(\d+)\/(\d+)\/(\d+) mbufs in use \(current\/cache\/total\)$/;
$nsre2  = qr/^(\d+)\/(\d+)\/(\d+)\/(\d+) mbuf clusters in use \(current\/cache\/total\/max\)$/;
$nsre3  = qr/^(\d+)\/(\d+) mbuf\+clusters out of packet secondary zone in use \(current\/cache\)$/;
$nsre4  = qr/^(\d+)\/(\d+)\/(\d+)\/(\d+) 4k \(page size\) jumbo clusters in use \(current\/cache\/total\/max\)$/;
$nsre5  = qr/^(\d+)\/(\d+)\/(\d+)\/(\d+) 9k jumbo clusters in use \(current\/cache\/total\/max\)$/;
$nsre6  = qr/^(\d+)\/(\d+)\/(\d+)\/(\d+) 16k jumbo clusters in use \(current\/cache\/total\/max\)$/;
$nsre7  = qr/^(\d+)K\/(\d+)K\/(\d+)K bytes allocated to network \(current\/cache\/total\)$/;
$nsre8  = qr/^(\d+)\/(\d+)\/(\d+) requests for mbufs denied \(mbufs\/clusters\/mbuf\+clusters\)$/;
$nsre9  = qr/^(\d+)\/(\d+)\/(\d+) requests for jumbo clusters denied \(4k\/9k\/16k\)$/;
$nsre10 = qr/^(\d+)\/(\d+)\/(\d+) sfbufs in use \(current\/peak\/max\)$/;
$nsre11 = qr/^(\d+) requests for sfbufs denied$/;
$nsre12 = qr/^(\d+) requests for sfbufs delayed$/;
$nsre13 = qr/^(\d+) requests for I\/O initiated by sendfile$/;
$nsre14 = qr/^(\d+) calls to protocol drain routines$/;

$hn = `hostname -s`;
chomp($hn);
$hn =~ s/\./_/g;

sub carbon_connect {
	$socket = IO::Socket::INET->new (
		PeerAddr => $carbon_host,
		PeerPort => $carbon_port,
		Proto => 'tcp',
	);
	if (!$socket) {
		print "Unable to connect!\n";
	}
}

sub csend {
	( $metric, $val ) = @_;
	$socket->send("netstat.${hn}.${metric} ${val} ${ts}\n");
}

carbon_connect;

while (1) {
	@netstat = `netstat -m`;
	$ts = time();

	if (!$socket->connected) {
		carbon_connect;
	}

	foreach $line (@netstat) {
		chomp($line);
		if ($line =~ $nsre1) {
			csend("mbufs.current", $1);
			csend("mbufs.cache", $2);
			csend("mbufs.total", $3);
		}
		if ($line =~ $nsre2) {
			csend("mbufcls.current", $1);
			csend("mbufcls.cache", $2);
			csend("mbufcls.total", $3);
			csend("mbufcls.max", $4);
		}
		if ($line =~ $nsre3) {
			csend("mbuf_and_mbufcls_out_of_packet_secondary_zone_in_use.current", $1);
			csend("mbuf_and_mbufcls_out_of_packet_secondary_zone_in_use.cache", $2);
		}
		if ($line =~ $nsre4) {
			csend("mbufcls.jumbo.4k.current", $1);
			csend("mbufcls.jumbo.4k.cache", $2);
			csend("mbufcls.jumbo.4k.total", $3);
			csend("mbufcls.jumbo.4k.max", $4);
		}
		if ($line =~ $nsre5) {
			csend("mbufcls.jumbo.9k.current", $1);
			csend("mbufcls.jumbo.9k.cache", $2);
			csend("mbufcls.jumbo.9k.total", $3);
			csend("mbufcls.jumbo.9k.max", $4);
		}
		if ($line =~ $nsre6) {
			csend("mbufcls.jumbo.16k.current", $1);
			csend("mbufcls.jumbo.16k.cache", $2);
			csend("mbufcls.jumbo.16k.total", $3);
			csend("mbufcls.jumbo.16k.max", $4);
		}
		if ($line =~ $nsre7) {
			csend("memalloc.current", $1 * 1024);
			csend("memalloc.cache", $2 * 1024);
			csend("memalloc.total", $3 * 1024);
		}
		if ($line =~ $nsre8) {
			csend("requestsdenied.mbufs.mbufs", $1);
			csend("requestsdenied.mbufs.clusters", $2);
			csend("requestsdenied.mbufs.mbuf_and_clusters", $3);
		}
		if ($line =~ $nsre9) {
			csend("requestsdenied.jumbocls.4k", $1);
			csend("requestsdenied.jumbocls.9k", $2);
			csend("requestsdenied.jumbocls.16k", $3);
		}
		if ($line =~ $nsre10) {
			csend("sfbufs.current", $1);
			csend("sfbufs.cache", $2);
			csend("sfbufs.total", $3);
		}
		if ($line =~ $nsre11) {
			csend("requestsdenied.sfbufs", $1);
		}
		if ($line =~ $nsre12) {
			csend("requestsdelayed.sfbufs", $1);
		}
		if ($line =~ $nsre13) {
			csend("sendfileioreqs", $1);
		}
		if ($line =~ $nsre14) {
			csend("protodraincalls", $1);
		}
	}
	undef(@netstat);
	sleep 10;
}

$socket->shutdown(2);


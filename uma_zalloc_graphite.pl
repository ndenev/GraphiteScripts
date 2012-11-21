#!/usr/bin/perl

use IO::Socket;

my $carbon_host = "graphite";
my $carbon_port = "2003";

my $socket;

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
	$socket->send("uma.${hn}.${metric} ${val} ${ts}\n");
}

carbon_connect;

while (1) {
	@vmstat = `vmstat -z`;
	$ts = time();

	if (!$socket->connected) {
		carbon_connect;
	}

	foreach $line (@vmstat) {
		chomp($line);
		if ($line =~ /^([a-zA-Z0-9_\s]+):\s+(\d+),\s+(\d+),\s+(\d+),\s+(\d+),\s+(\d+),\s+(\d+)$/) {
			$item = $1;
			$i_size = $2;
			$i_limit = $3;
			$i_used = $4;
			$i_free = $5;
			$i_requests = $6;
			$i_failures = $7;
			$item =~ s/[ \.\/]+/_/g;
			csend("$item.size", $i_size);
			csend("$item.limit", $i_limit);
			csend("$item.used", $i_used);
			csend("$item.free", $i_free);
			csend("$item.requests", $i_requests);
			csend("$item.failures", $i_failures);
		}
	}
	undef(@vmstat);
	sleep 10;
}

$socket->shutdown(2);


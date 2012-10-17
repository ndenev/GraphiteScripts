#!/usr/bin/perl

use IO::Socket;

my $carbon_host = "graphite";
my $carbon_port = "2003";

my $socket;

open NFSSTAT,"nfsstat -s 10|";


$hn = `hostname`;
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

carbon_connect;

while (<NFSSTAT>) {
	$line = $_;
	chomp($line);

	if (!$socket->connected) {
		carbon_connect;
	}

	if ($line =~ /^\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)$/) {
		$ts = time();
		$socket->send("${hn}.nfsd.gtattr $1 ${ts}\n");
		$socket->send("${hn}.nfsd.lookup $2 ${ts}\n");
		$socket->send("${hn}.nfsd.rdlink $3 ${ts}\n");
		$socket->send("${hn}.nfsd.read $4 ${ts}\n");
		$socket->send("${hn}.nfsd.write $5 ${ts}\n");
		$socket->send("${hn}.nfsd.rename $6 ${ts}\n");
		$socket->send("${hn}.nfsd.access $7 ${ts}\n");
		$socket->send("${hn}.nfsd.rddir $8 ${ts}\n");
	}
}

$socket->shutdown(2);


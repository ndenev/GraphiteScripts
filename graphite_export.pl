#!/usr/bin/perl

# Copyright (c) <2012>, Nikolay Denev <ndenev@gmail.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

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
		if (!$socket->connected) {
			carbon_connect;
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


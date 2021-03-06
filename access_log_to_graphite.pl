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

# $Id:$

use warnings;
use strict;
use File::Tail;
use IO::Socket;
use Data::Dumper;
use Sys::Hostname;
use POSIX qw(:signal_h);

##########

my $log_file_pattern = "/var/log/httpd-*-access.log";

my $app_url_pattern = qr/.*/o;
my $access_log_pattern = qr/^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) - (.*) \[(.*)\] ([A-Z]+\s.*\sHTTP\/[0-9]+\.[0-9]+|-|)\s+"([0-9]+)" ([0-9]+) "([^"]+)" "([^"]+)" "([^"]+)" "(.*):(.*)" \("([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+|-)" "([0-9]+|-)" "([0-9]+\.[0-9]+|-)"\) ([0-9]+\.[0-9]+)$/o;
my $request_pattern = qr/^([A-Z]+) (.*) HTTP\/([0-9]+\.[0-9]+)$/o;
my $upstream_pattern = qr/^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)$/o;

my $carbon_host = 'carbon';
my $carbon_port = '2013';

my $hostname = hostname;
$hostname =~ s/\./-/;
my $metric_prefix = "nginx.${hostname}";
my $interval = 5;
my $DEBUG=10;

##########

my (%metrics_avg, %metrics_avg_cnt, %metrics_sum);

sub main;
sub send_metrics;
sub carbon_connect;
sub parse;
sub cyclic;

my $carbon_socket;

################
main;
################


sub main {

	while (!carbon_connect($carbon_host, $carbon_port)) {
		debug(0, "initial connection to carbon failed, retrying...");
		sleep 1;
	}

	my @logfiles;

	my $ss = POSIX::SigSet->new(SIGALRM);
	my $oss = POSIX::SigSet->new;

	local $SIG{ALRM} = "cyclic";
	alarm $interval;

	foreach (glob $log_file_pattern) {
		debug(1, "opening $_...");
		push(@logfiles,File::Tail->new(name=>"$_", interval=>5, maxinterval=>20, tail=>0, reset_tail=>0));
	}

	while (1) {
		my ($nfound, $timeleft, @pending) = File::Tail::select(undef,undef,undef,undef,@logfiles);
		unless ($nfound) {
			debug(2, "timeout without new data...");
		} else {
			foreach (@pending) {
				sigprocmask(SIG_BLOCK, $ss, $oss);
				parse($_->{"input"}, $_->read);
				sigprocmask(SIG_UNBLOCK, $oss);
			}
		}
	}
	$carbon_socket->shutdown(2);
}

sub parse {
	my $line;
	my $file;
	my $clientip;
	my $clientuser;
	my $time;
	my $rawreq;
	my $http_resp;
	my $bytes;
	my $http_ref;
	my $http_ua;
	my $http_xff;
	my $http_sslproto;
	my $http_sslcipher;
	my $upstreaminfo;
	my $upstreamstatus;
	my $upstreamtime;
	my $requesttime;
	my $verb;
	my $request;
	my $http_ver;
	my $upstreamaddr;
	my $upstreamport;
	($file, $line) = @_;
        if ($line =~ $access_log_pattern) {
		$clientip = $1;
		$clientuser = $2;
		$time = $3;
		$rawreq = $4;
		$http_resp = $5;
		$bytes = $6;
		$http_ref = $7;
		$http_ua = $8;
		$http_xff = $9;
		$http_sslproto = $10;
		$http_sslcipher = $11;
		$upstreaminfo = $12;
		$upstreamstatus = $13;
		$upstreamtime = $14;
		$requesttime = $15;
		if ($rawreq =~ $request_pattern) {
			$verb = $1;
			$request = $2;
			$http_ver = $3;
		} else {
			$verb = $request = $http_ver = "-";
		}
		# XXX: must be able to parse multiple upstream reponses
		if ($upstreaminfo =~ $upstream_pattern) {
			$upstreamaddr = $1;
			$upstreamport = $2;
		} else {
			$upstreamaddr = $upstreamport = "-";
		}

		# Sanitize log file name
		$file =~ s/^.*\/(.*)$/$1/;
		$file =~ s/\./-/g;

		# Global stats
		$metrics_sum{"bytes.total"} += $bytes;
		$metrics_sum{"bytes.log.${file}.total"} += $bytes;
		$metrics_sum{"requests.total"}++;
		$metrics_sum{"requests.log.${file}.total"}++;
		$metrics_avg{"requesttime.total"} += $requesttime;
		$metrics_avg_cnt{"requesttime.total"}++;
		$metrics_avg{"requesttime.log.${file}.total"} += $requesttime;
		$metrics_avg_cnt{"requesttime.log.${file}.total"}++;

		# Stats per http response code
		$metrics_sum{"bytes.http_response.$http_resp"} += $bytes;
		$metrics_sum{"requests.http_response.$http_resp"}++;
		$metrics_avg{"requesttime.http_response.$http_resp"} += $requesttime;
		$metrics_avg_cnt{"requesttime.http_response.$http_resp"}++;

		# Stats per verb
		$metrics_sum{"bytes.verb.${verb}"} += $bytes;
		$metrics_sum{"requests.verb.${verb}"}++;
		$metrics_avg{"requesttime.verb.${verb}"} += $requesttime;
		$metrics_avg_cnt{"requesttime.verb.${verb}"}++;

		# Stats per application urls
		if (($request =~ $app_url_pattern) && ($http_resp != 404)) {
			# Clean up chars used as graphite delimiters
			$request =~ s/\./_/g;
			$request =~ s/^\///;
			# Clean up GET requests data
			$request =~ s/^([^?]+)\?.*/$1/g;
			$metrics_sum{"bytes.url.app.${request}"} += $bytes;
			$metrics_sum{"requests.url.app.${request}.total"}++;
			$metrics_sum{"requests.url.app.${request}.http_response.${http_resp}"}++;
			$metrics_avg{"requesttime.url.app.${request}"} += $requesttime;
			$metrics_avg_cnt{"requesttime.url.app.${request}"}++;
			$metrics_sum{"requests.url.app.${request}.verb.${verb}"}++;
		}
	} else {
		print "XXX UNPARSED LINE: $line\n";
	}
}

sub carbon_connect {
	my ($carbon_host, $carbon_port) = @_;
	$carbon_socket = IO::Socket::INET->new (
		PeerAddr => $carbon_host,
		PeerPort => $carbon_port,
		Proto => 'tcp',
	);
	debug(0, "Unable to open socket: $!") unless ($carbon_socket);
	return $carbon_socket;
}

sub send_metrics {
	debug(3, "sending metrics");
	my $key;
	my $ts = time();

	foreach $key (keys %metrics_sum) {
		while (!$carbon_socket->send($metric_prefix . "." . $key . " " . $metrics_sum{$key} . " " . $ts . "\n")) {
			debug(0, "connection to carbon failed, retrying in one second...");
			sleep 1;
			carbon_connect($carbon_host, $carbon_port);
		}
		debug(10, $metric_prefix . "." . $key . " " . $metrics_sum{$key} . " " . $ts);
	}
	foreach $key (keys %metrics_avg) {
		while (!$carbon_socket->send($metric_prefix . "." . $key . " " . $metrics_avg{$key} / $metrics_avg_cnt{$key} . " " . $ts . "\n")) {
			debug(0, "connection to carbon failed, retrying in one second...");
			sleep 1;
			carbon_connect($carbon_host, $carbon_port);
		}
		debug(10, $metric_prefix . "." . $key . " " . $metrics_avg{$key} / $metrics_avg_cnt{$key} . " " . $ts);
	}

	undef(%metrics_avg);
	undef(%metrics_avg_cnt);
	undef(%metrics_sum);
}

sub debug {
	my ($debuglevel, $msg) = @_;
	if ($DEBUG >= $debuglevel) {
		print "$msg\n";
	}
}

sub cyclic {
	send_metrics;
	alarm $interval;
}

#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;
use FindBin qw($RealBin);
use lib $RealBin;
use DNSBench qw(query now);
use ClientWorkload qw(run_phase);
use JSON::PP qw(encode_json);
use Time::HiRes qw(sleep);
use Socket qw(AF_INET inet_pton);
my ($action,$address,@args)=@ARGV;
defined $action && defined $address && $address =~ /\A[0-9.]+\z/ && inet_pton(AF_INET,$address)
    or die "numeric lab resolver IPv4 required\n";
if ($action eq 'probe' && @args==2) {
    my ($proto,$name)=@args;
    $name =~ /\A(?:warm|recovery)\.bench\.test\.\z/ or die "invalid probe name\n";
    my $end=now()+15;
    while (now()<$end) {
        my ($result)=query(5353,$proto,$name,1,$address);
        if ($result eq 'ok') {print "ok\n"; exit 0;}
        sleep 0.5;
    }
    die "fixture/recovery probe failed for $proto\n";
}
if ($action eq 'phase' && @args==5) {
    print encode_json(run_phase($address,5353,@args)),"\n";
    exit 0;
}
die "invalid benchmark client command\n";

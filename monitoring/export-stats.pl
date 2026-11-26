#!/usr/bin/env perl
# Convert one successful stats_noreset output to an atomically published snapshot.
# Run as an approved operator, not as Telegraf. No Docker calls or credentials here.
use v5.26;
use strict;
use warnings;
use File::Temp qw(tempfile);
use File::Basename qw(dirname);
my ($path) = @ARGV;
defined($path) && @ARGV == 1 && $path =~ m{\A/} && !-l $path or die "usage: export-stats.pl /protected/path/stats.lp\n";
my @required = qw(total.num.queries total.num.cachehits total.num.cachemiss total.recursion.time.avg);
my %allowed = map { $_ => 1 } (@required, qw(total.num.recursivereplies total.num.queries_ip_ratelimited num.answer.rcode.SERVFAIL num.answer.rcode.NXDOMAIN num.query.type.A num.query.type.AAAA num.query.type.TXT num.query.type.PTR num.query.tcp num.query.udp mem.cache.rrset mem.cache.message time.up));
my (%fields, $size);
while (my $line = <STDIN>) {
    $size += length($line);
    $size <= 262144 or die "stats input too large\n";
    chomp $line;
    my ($key, $val) = split /=/, $line, 2;
    next unless $allowed{$key};
    defined($val) && $val =~ /\A[0-9]{1,18}(?:\.[0-9]{1,12})?\z/ or die "invalid metric: $key\n";
    !exists $fields{$key} or die "duplicate metric: $key\n";
    $fields{$key} = $val;
}
for (@required) { exists $fields{$_} or die "missing required metric: $_\n"; }
my @out = map { my $name = $_; $name =~ s/\./_/g; "$name=$fields{$_}" } sort keys %fields;
my $line = 'unbound_snapshot,service=unbound-recursive ' . join(',', @out) . ' ' . time() . "000000000\n";
my ($fh, $tmp) = tempfile('.stats-XXXXXXXX', DIR => dirname($path), UNLINK => 0);
# Protected setgid directory determines the monitoring group. Never grant write to Telegraf.
chmod 0640, $tmp or die "chmod: $!\n";
print {$fh} $line or die "write: $!\n";
close $fh or die "close: $!\n";
rename $tmp, $path or die "rename: $!\n";

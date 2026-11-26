#!/usr/bin/env perl
# Run only from the approved deployment directory, under an authorized operator.
use v5.26;
use strict;
use warnings;
use FindBin qw($RealBin);
use File::Temp qw(tempfile);
use Fcntl qw(:flock O_CREAT O_RDWR O_NOFOLLOW);
my ($path) = @ARGV;
@ARGV == 1 && $path =~ m{\A/} && !-l $path or die "usage: collect-stats.pl /protected/path/unbound.lp\n";
-f 'compose.yaml' or die "run from the reviewed deployment directory\n";
umask 077;
sysopen(my $lock, "$path.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0600) or die "open collection lock: $!\n";
flock($lock, LOCK_EX | LOCK_NB) or die "collection already running\n";
my ($tmp) = tempfile(UNLINK => 1);
# Do not pipe partial or failed Docker output into the atomic exporter.
open my $in, '-|', 'docker', 'compose', '-f', 'compose.yaml', 'exec', '-T', 'unbound',
    'unbound-control', '-c', '/etc/unbound/recursive.conf', 'stats_noreset' or die "start stats collection: $!\n";
my $size = 0;
while (1) {
    my $read = read($in, my $chunk, 8192);
    defined $read or die "read stats: $!\n";
    last unless $read;
    $size += length($chunk);
    $size <= 262144 or die "stats input too large\n";
    print {$tmp} $chunk or die "write temporary stats: $!\n";
}
close $in or die "Unbound stats collection failed\n";
seek($tmp, 0, 0) or die "seek temporary stats: $!\n";
open STDIN, '<&', $tmp or die "redirect input: $!\n";
# Keep the lock in this process while the exporter executes.
system {$^X} $^X, "$RealBin/export-stats.pl", $path;
$? == 0 or die "stats export failed\n";

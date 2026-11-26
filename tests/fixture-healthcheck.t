use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use ProjectTest qw(write_bytes run_command read_bytes);
use File::Temp qw(tempdir);
my $dir=tempdir(CLEANUP=>1);
my $script="$FindBin::Bin/../benchmark/fixture-healthcheck.sh";
write_bytes("$dir/timeout", <<'SH');
#!/bin/sh
[ "$*" = '-k 1s 3s drill -u -p 5354 bench.test. @127.0.0.1 A' ] || exit 90
cat "$PROBE_REPLY"
exit "$PROBE_EXIT"
SH
chmod 0755,"$dir/timeout" or die $!;
local $ENV{PATH}="$dir:$ENV{PATH}";
local $ENV{PROBE_REPLY}="$dir/reply";
local $ENV{PROBE_EXIT}=0;
my $reply=<<'DNS';
;; ->>HEADER<<- opcode: QUERY, rcode: NOERROR, id: 123
;; flags: qr aa rd ra ; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0
;; QUESTION SECTION:
;; bench.test. IN A
;; ANSWER SECTION:
bench.test. 300 IN A 192.0.2.80
;; AUTHORITY SECTION:
DNS
sub probe {write_bytes($ENV{PROBE_REPLY},$_[0]); return run_command(['/bin/sh',$script])->{code};}
is(probe($reply),0,'actual fixture name, port and expected A answer');
isnt(probe($reply =~ s/NOERROR/SERVFAIL/r),0,'fixture SERVFAIL rejected');
isnt(probe($reply =~ s/192\.0\.2\.80/192.0.2.53/r),0,'resolver health record rejected');
isnt(probe($reply =~ s/flags: qr/flags: qr tc/r),0,'truncated reply rejected');
{local $ENV{PROBE_EXIT}=124; isnt(probe($reply),0,'probe timeout rejected');}
my $compose=read_bytes("$FindBin::Bin/../benchmark/compose.yaml");
like($compose,qr{test: \[CMD, /bin/sh, /bench-healthcheck\.sh\]},'fixture healthcheck is configured');
unlike($compose,qr/healthcheck: \{disable: true\}/,'no disabled healthcheck in wait-based lab');
done_testing;

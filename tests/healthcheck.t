use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use ProjectTest qw(write_bytes run_command);
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);
my $script = "$FindBin::Bin/../scripts/healthcheck.sh";
# Mock only the external probe; exercise the actual shell parser and arguments.
write_bytes("$dir/timeout", <<'SH');
#!/bin/sh
[ "$*" = "-k 1s 3s drill $PROBE_TRANSPORT -p 5353 resolver-health.test. @127.0.0.1 A" ] || exit 90
cat "$PROBE_REPLY"
exit "$PROBE_EXIT"
SH
chmod 0755, "$dir/timeout" or die "chmod: $!";
local $ENV{PATH} = "$dir:$ENV{PATH}";
local $ENV{PROBE_REPLY} = "$dir/reply";
local $ENV{PROBE_TRANSPORT} = '-u';
local $ENV{PROBE_EXIT} = 0;
my $reply = <<'DNS';
;; ->>HEADER<<- opcode: QUERY, rcode: NOERROR, id: 123
;; flags: qr aa rd ra ; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0
;; QUESTION SECTION:
;; resolver-health.test. IN A

;; ANSWER SECTION:
resolver-health.test.	60	IN	A	192.0.2.53

;; AUTHORITY SECTION:

;; ADDITIONAL SECTION:
;; Query time: 0 msec
;; SERVER: 127.0.0.1
DNS
sub probe {
    my ($data, @args) = @_;
    write_bytes($ENV{PROBE_REPLY}, $data);
    return run_command([$script, @args])->{code};
}
is(probe($reply), 0, 'UDP local record is healthy');
{
    local $ENV{PROBE_TRANSPORT} = '-t';
    is(probe($reply, '--tcp'), 0, 'TCP local record is healthy');
}
isnt(probe($reply, '--invalid'), 0, 'unsupported option refused');
isnt(probe($reply =~ s/NOERROR/SERVFAIL/r), 0, 'SERVFAIL refused');
isnt(probe($reply =~ s/NOERROR/NXDOMAIN/r), 0, 'NXDOMAIN refused');
isnt(probe($reply =~ s/192\.0\.2\.53/192.0.2.54/r), 0, 'wrong address refused');
isnt(probe($reply =~ s/\tIN\tA\t/\tIN\tTXT\t/r), 0, 'wrong type refused');
isnt(probe($reply =~ s/^resolver-health\.test\./other.test./mr), 0, 'wrong name refused');
isnt(probe($reply =~ s/;; ANSWER SECTION:/;; AUTHORITY SECTION:/r), 0, 'record outside answer refused');
isnt(probe($reply =~ s/^resolver-health\.test\..*\n//mr), 0, 'missing answer refused');
isnt(probe($reply =~ s/^(resolver-health\.test\..*)$/$1\n$1/mr), 0, 'duplicate answer refused');
isnt(probe($reply =~ s/flags: qr/flags: qr tc/r), 0, 'truncated response refused');
isnt(probe($reply =~ s/flags: qr /flags: /r), 0, 'nonresponse refused');
isnt(probe(''), 0, 'empty reply refused');
{
    local $ENV{PROBE_EXIT} = 124;
    isnt(probe($reply), 0, 'timeout fails even with apparent valid output');
}
done_testing;

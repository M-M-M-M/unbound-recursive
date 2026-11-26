use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use ProjectTest qw(run_command);
# Child-local limit: exercise the failure on macOS and Linux without changing
# the operator's shell limit. No dependency on /proc or external lsof.
my $program = <<'PERL';
use strict; use warnings;
use ProjectTest qw(run_command);
for (1..200) {
    my $r=run_command([$^X,'-e','print scalar <STDIN>; warn "diagnostic\n"; exit 7'],"payload\n",5);
    die 'capture mismatch' unless $r->{code}==7 && $r->{stdout} eq "payload\n" && $r->{stderr} eq "diagnostic\n";
}
for (1..20) {
    eval {run_command([$^X,'-e','sleep 10'],'',0.03)};
    die 'timeout missing' unless $@ =~ /timed out/;
    eval {run_command([$^X,'-e','sleep 10'],'',5,sub {die "watchdog test\n"})};
    die 'watchdog missing' unless $@ =~ /watchdog test/;
}
my $r=run_command([$^X,'-e','print "still alive"'],'',5);
die 'final capture failed' unless $r->{code}==0 && $r->{stdout} eq 'still alive';
PERL
my $r=run_command(['/bin/sh','-c','ulimit -n 64 || exit 99; exec "$@"','sh',$^X,"-I$FindBin::Bin/lib",'-e',$program],'',30);
is($r->{code},0,'200 commands and 40 exceptional exits under a 64-descriptor limit') or diag($r->{stderr});
done_testing;

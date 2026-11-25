use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use ProjectTest qw(write_bytes confirm_command);
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);
my $fixture = "$dir/confirmation-fixture";
write_bytes($fixture, <<'FIXTURE');
#!/usr/bin/env perl
use strict;
use warnings;
use IO::Select;
use Time::HiRes qw(sleep);
$| = 1;
-t STDIN or die "not a terminal\n";
# A premature line of input is a test failure, not a confirmation.
exit 31 if IO::Select->new(\*STDIN)->can_read(0.25);
print "Type YES to ";
sleep 0.1;
print "continue: ";
my $line = <STDIN>;
exit 32 unless defined $line;
chomp $line;
exit($line eq 'YES' ? 0 : 33);
FIXTURE
chmod 0755, $fixture or die "chmod fixture: $!";
my $r = confirm_command($fixture, 'test', 'YES');
is($r->{code}, 0, 'confirmation sent only after delayed split prompt') or diag($r->{stdout}, $r->{stderr});
$r = confirm_command($fixture, 'test', 'NO');
is($r->{code}, 33, 'incorrect confirmation remains rejected') or diag($r->{stdout}, $r->{stderr});
done_testing;

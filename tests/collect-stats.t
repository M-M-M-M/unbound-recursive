use v5.26;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use Cwd qw(getcwd);
use FindBin;
use lib "$FindBin::Bin/lib";
use ProjectTest qw(run_command read_bytes write_bytes);
use Fcntl qw(:flock);
my $dir=tempdir(CLEANUP=>1);
my $cwd=getcwd();
my $script="$FindBin::Bin/../monitoring/collect-stats.pl";
chdir $dir or die $!;
write_bytes('compose.yaml', "services: {}\n");
write_bytes('docker', <<'MOCK');
#!/bin/sh
printf 'total.num.queries=123\ntotal.num.cachehits=100\ntotal.num.cachemiss=23\ntotal.recursion.time.avg=0.1\n'
exit "${MOCK_EXIT:-0}"
MOCK
chmod 0755, 'docker';
local $ENV{PATH}="$dir:$ENV{PATH}";
my $file="$dir/unbound.lp";
sub invoke { run_command([$^X,$script,$file], '',10) }
is(invoke()->{code},0,'successful collection');
my $before=read_bytes($file);
like($before,qr/total_num_queries=123/,'complete snapshot published');
{ local $ENV{MOCK_EXIT}=1; isnt(invoke()->{code},0,'failed Docker collection propagates'); }
is(read_bytes($file),$before,'failed collection preserves snapshot');
open my $lock,'>>',"$file.lock" or die $!;
flock($lock,LOCK_EX) or die $!;
isnt(invoke()->{code},0,'concurrent collection refused');
close $lock or die $!;
unlink "$file.lock" or die $!;
symlink "$dir/compose.yaml", "$file.lock" or die $!;
isnt(invoke()->{code},0,'symlink lock refused');
chdir $cwd or die $!;
done_testing;

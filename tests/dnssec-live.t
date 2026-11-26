use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use Cwd qw(abs_path);
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use ProjectTest qw(run_command read_bytes);
use LocalDocker qw(require_local_docker);
use File::Temp qw(tempdir);
plan skip_all => 'opt in with make test-dnssec' unless ($ENV{RUN_DNSSEC_LIVE}//'') eq '1';
require_local_docker();
my $dir=tempdir('dnssec-fixture-XXXXXXXX', TMPDIR=>1, CLEANUP=>1);
my ($name)=$dir=~m{([^/]+)\z};
$name=lc $name; $name =~ tr{_}{-};
my $image='unbound-recursive:dev';
my $parser=abs_path("$FindBin::Bin/dnssec-reply.sh");
my $result=eval { run_command(['docker','run','--rm','-i','--name',$name,'--pull','never','--network','none','--read-only','--user','10001:10001','--cap-drop','ALL','--security-opt','no-new-privileges:true','--memory','128m','--cpus','1','--pids-limit','32','--tmpfs','/tmp:uid=10001,gid=10001,mode=0700,size=16m','--mount',"type=bind,src=$parser,dst=/dnssec-reply.sh,readonly",'--no-healthcheck','--entrypoint','/bin/sh',$image,'-s'],read_bytes("$FindBin::Bin/dnssec-fixture.sh"),120) };
my $error=$@;
# On timeout the Docker CLI may have died before the container; remove by unique name.
if (!$result) { eval {run_command(['docker','rm','-f',$name],'',30)}; fail('isolated DNSSEC fixture completed'); diag($error); done_testing; exit; }
ok(!$result->{code},'isolated DNSSEC fixture completed') or diag($result->{stdout},$result->{stderr});
like($result->{stdout},qr/^DNSSEC positive: PASS$/m,'valid signature accepted with AD');
like($result->{stdout},qr/^DNSSEC negative: PASS$/m,'altered signed answer refused with SERVFAIL');
like($result->{stdout},qr/^DNSSEC checking-disabled control: PASS$/m,'altered answer exists with checking disabled');
done_testing;

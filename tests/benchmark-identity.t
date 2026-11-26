use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../benchmark";
use RunIdentity qw(project_name);
for my $suffix ('_QOIlXWz','________','a_B_C_D_','ABCDEFGH','a1234567') {
    my $name=project_name("/tmp/unbound-bench-$suffix");
    like("$name-client:local",qr/\A[a-z0-9]+(?:-+[a-z0-9]+)*:local\z/,'valid Docker repository');
    unlike($name,qr/_/,'no underscores');
}
ok(!eval {project_name('/tmp/other');1},'unexpected name rejected');
done_testing;

use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use ProjectTest qw(run_command);

my $script = "$FindBin::Bin/package-policy.sh";
my $baseline = "ii \tunbound\nii \tldnsutils\nii \tlibldns3t64:arm64\n";
sub check { return run_command([$script], $_[0]); }
is(check($baseline)->{code}, 0, 'minimal installed package set allowed');
for my $pkg (qw(bind9 bind9-dnsutils bind9-libs:amd64 liblmdb0:arm64 libxml2:amd64 libxml2-16)) {
    my $result = check($baseline . "ii \t$pkg\n");
    isnt($result->{code}, 0, "$pkg rejected");
    like($result->{stdout}, qr/\Q$pkg\E/, "$pkg identified");
}
is(check($baseline . "rc \tbind9-dnsutils\n")->{code}, 0, 'removed package is not an installed dependency');
isnt(check('')->{code}, 0, 'missing inventory rejected');
isnt(check("ii \tunbound\n")->{code}, 0, 'missing ldnsutils rejected');
isnt(check("ii \tldnsutils\n")->{code}, 0, 'missing unbound rejected');
done_testing;

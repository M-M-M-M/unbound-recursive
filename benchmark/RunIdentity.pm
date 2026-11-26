package RunIdentity;
use v5.26;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(project_name);
sub project_name {
    my ($dir) = @_;
    $dir =~ m{(?:\A|/)(unbound-bench-[A-Za-z0-9_]{8})\z} or die "invalid benchmark directory identity\n";
    my $name = lc $1;
    $name =~ tr/_/-/;
    return $name;
}
1;

package LocalDocker;
use v5.26;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK=qw(require_local_docker);
# Prevent a local loopback test from accidentally targeting a remote daemon.
sub require_local_docker {
    my $host;
    if (!length($ENV{DOCKER_CONTEXT}//'') && length($ENV{DOCKER_HOST}//'')) {
        $host=$ENV{DOCKER_HOST};
    } else {
        open my $fh,'-|','docker','context','inspect','--format','{{.Endpoints.docker.Host}}' or die "inspect Docker context: $!\n";
        $host=<$fh>//''; close $fh or die "cannot inspect Docker context\n";
        chomp $host;
    }
    $host =~ m{\Aunix:///[^\r\n]+\z} or die "a local Unix-socket Docker context is required for this lab\n";
    return 1;
}
1;

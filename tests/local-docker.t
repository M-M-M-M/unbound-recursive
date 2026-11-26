use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use LocalDocker qw(require_local_docker);
local $ENV{DOCKER_CONTEXT}='';
for my $endpoint ('unix:///var/run/docker.sock','unix:///Users/operator/.docker/run/docker.sock') {
    local $ENV{DOCKER_HOST}=$endpoint;
    ok(eval {require_local_docker()},'accept local Unix endpoint');
}
for my $endpoint ('ssh://example.test','tcp://127.0.0.1:2375','http://example.test') {
    local $ENV{DOCKER_HOST}=$endpoint;
    ok(!eval {require_local_docker()},'reject non-Unix endpoint');
}
done_testing;

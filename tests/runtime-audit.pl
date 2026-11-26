#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use ProjectTest qw(run_command read_bytes);
use LocalDocker qw(require_local_docker);
require_local_docker();
my $image='unbound-recursive:dev';
my $id=run_command(['docker','image','inspect','--format','{{.Id}}',$image],'',30);
die "build local image first: $id->{stderr}" if $id->{code};
my $immutable=$id->{stdout}; chomp $immutable;
die 'invalid image ID' unless $immutable =~ /\Asha256:[0-9a-f]{64}\z/;
print "Image ID: $immutable\n";
my $audit=run_command(['docker','run','--rm','-i','--pull','never','--network','none','--read-only','--user','10001:10001','--cap-drop','ALL','--security-opt','no-new-privileges:true','--memory','128m','--pids-limit','32','--tmpfs','/state:uid=10001,gid=10001,mode=0750,size=1m','--tmpfs','/run/resolver:uid=10001,gid=10001,mode=0750,size=1m','--no-healthcheck','--entrypoint','/bin/sh',$immutable,'-s'],read_bytes("$FindBin::Bin/runtime-audit.sh"),120);
print $audit->{stdout};
print STDERR $audit->{stderr};
exit $audit->{code};

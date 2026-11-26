package LabNetwork;
use v5.26;
use strict;
use warnings;
use Exporter 'import';
use Socket qw(AF_INET inet_pton);
our @EXPORT_OK=qw(validate_lab_network);

# Inspect actual Docker objects, not merely Compose declarations. The fixture
# shares the resolver namespace; only the resolver and client join the bridge.
sub validate_lab_network {
    my ($network,$resolver,$client,$fixture)=@_;
    my $nid=$network->{Id}//'';
    $nid =~ /\A[0-9a-f]{64}\z/ && $network->{Internal} &&
        ($network->{Driver}//'') eq 'bridge' && !$network->{EnableIPv6}
        or die "benchmark network must be an internal IPv4 bridge\n";
    my %expected=map {($_->{Id}//'')=>1} ($resolver,$client);
    keys(%expected)==2 && !exists $expected{''} or die "invalid benchmark containers\n";
    my $members=$network->{Containers}//{};
    keys(%$members)==2 && !grep {!exists $expected{$_}} keys %$members
        or die "unexpected benchmark network membership\n";
    my @ips;
    for my $c ($resolver,$client,$fixture) {
        my $hc=$c->{HostConfig}//{};
        !keys(%{$hc->{PortBindings}//{}}) && !$hc->{PublishAllPorts}
            or die "benchmark container has published ports\n";
        !grep {defined($_) && @$_} values %{$c->{NetworkSettings}{Ports}//{}}
            or die "benchmark container has active host bindings\n";
        if ($c==$fixture) {
            ($hc->{NetworkMode}//'') eq "container:$resolver->{Id}"
                or die "fixture must share resolver network namespace\n";
            next;
        }
        my $nets=$c->{NetworkSettings}{Networks}//{};
        keys(%$nets)==1 or die "benchmark container must join exactly one network\n";
        my ($endpoint)=values %$nets;
        ($endpoint->{NetworkID}//'') eq $nid or die "benchmark network ID mismatch\n";
        my $ip=$endpoint->{IPAddress}//'';
        $ip =~ /\A[0-9.]+\z/ && inet_pton(AF_INET,$ip) && $ip !~ /\A(?:0|127)\./
            or die "invalid benchmark endpoint\n";
        ($members->{$c->{Id}}{IPv4Address}//'') =~ /\A\Q$ip\E\/\d+\z/
            or die "benchmark endpoint mismatch\n";
        push @ips,$ip;
    }
    $ips[0] ne $ips[1] or die "benchmark endpoints must be distinct\n";
    return $ips[0];
}
1;

package ResourceEvidence;
use v5.26;
use strict;
use warnings;
use Exporter 'import';
use JSON::PP qw(decode_json);
use List::Util qw(max);
our @EXPORT_OK=qw(parse_stats coverage clock_anomaly container_healthy check_heartbeat);
sub memory_bytes {
    my ($s)=@_;
    return undef unless ($s//'') =~ /\A(\d+(?:\.\d+)?)(B|KiB|MiB|GiB)\s*\//;
    my %factor=(B=>1,KiB=>1024,MiB=>1048576,GiB=>1073741824);
    return $1*$factor{$2};
}
sub parse_stats {
    my ($raw,$ids,$elapsed,$epoch)=@_;
    my (@samples,@errors,%seen);
    for my $line (split /\n/,$raw) {
        my $s=eval {decode_json($line)};
        if (ref($s) ne 'HASH') {push @errors,'invalid JSON row'; next;}
        my $short=$s->{ID}//$s->{Container}//'';
        my ($role)=$short =~ /\A[0-9a-f]{12,64}\z/ ? grep {index($ids->{$_},$short)==0} sort keys %$ids : ();
        if (!defined $role) {push @errors,'unrecognized container'; next;}
        if ($seen{$role}++) {push @errors,"duplicate $role row"; next;}
        if (($s->{CPUPerc}//'') !~ /\A\d+(?:\.\d+)?%\z/ || !defined memory_bytes($s->{MemUsage})) {
            push @errors,"invalid $role CPU or memory"; next;
        }
        my %fields=map {$_=>$s->{$_}} grep {defined $s->{$_} && !ref($s->{$_})} qw(CPUPerc MemUsage MemPerc NetIO BlockIO PIDs);
        push @samples,{%fields,role=>$role,elapsed=>$elapsed,epoch=>$epoch};
    }
    for my $role (sort keys %$ids) {push @errors,"missing $role sample" unless grep {$_->{role} eq $role} @samples;}
    return (\@samples,\@errors);
}
sub median {
    my @v=sort {$a<=>$b} @_;
    return undef unless @v;
    return ($v[int(($#v)/2)]+$v[int(@v/2)])/2;
}
sub coverage {
    my ($samples,$duration,$interval)=@_;
    my %roles; my $complete=1;
    my $max_gap=$interval*2.5;
    for my $role (qw(resolver client)) {
        my @s=sort {$a->{elapsed}<=>$b->{elapsed}} grep {$_->{role} eq $role && $_->{elapsed}>=0 && $_->{elapsed}<=$duration+10} @$samples;
        my @t=map {$_->{elapsed}>$duration?$duration:$_->{elapsed}} @s;
        my @bounds=(0,@t,$duration);
        my $gap=max(map {$bounds[$_]-$bounds[$_-1]} 1..$#bounds);
        my $required=int(0.9*$duration/$interval);
        $required=1 if $required<1;
        my $ok=@s >= $required && $gap <= $max_gap;
        $complete &&= $ok;
        my @early=grep {defined} map {memory_bytes($_->{MemUsage})} grep {$_->{elapsed}>=$duration*0.5 && $_->{elapsed}<$duration*0.75} @s;
        my @tail=grep {defined} map {memory_bytes($_->{MemUsage})} grep {$_->{elapsed}>=$duration*0.75} @s;
        my ($early,$tail)=(median(@early),median(@tail));
        $roles{$role}={count=>scalar @s,required=>$required,first=>$t[0],last=>$t[-1],max_gap_seconds=>$gap,complete=>$ok?1:0,
            late_memory_bytes=>$early,tail_memory_bytes=>$tail,late_memory_change_bytes=>defined($early)&&defined($tail)?$tail-$early:undef};
    }
    return {complete=>$complete?1:0,interval_seconds=>$interval,max_allowed_gap_seconds=>$max_gap,roles=>\%roles};
}
sub clock_anomaly {
    my ($mono,$wall,$limit)=@_;
    return $mono<0 || $wall<0 || $mono>$limit || $wall>$limit || abs($wall-$mono)>5;
}
sub check_heartbeat {
    my ($last,$elapsed,$limit)=@_;
    for my $role (qw(resolver client)) {
        my $seen=$last->{$role}//0;
        $elapsed-$seen <= $limit or die "resource watchdog: missing $role sample for over $limit seconds\n";
    }
    return 1;
}
sub container_healthy {
    my ($before,$after)=@_;
    return defined($before->{RestartCount}) && defined($after->{RestartCount}) && $before->{RestartCount}==$after->{RestartCount}
        && $after->{State}{Running} && !$after->{State}{OOMKilled} && defined($before->{State}{StartedAt})
        && ($after->{State}{StartedAt}//'') eq $before->{State}{StartedAt};
}
1;

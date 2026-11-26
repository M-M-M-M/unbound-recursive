package DNSBench;
use v5.26;
use strict;
use warnings;
use Exporter 'import';
use IO::Socket::INET;
use IO::Select;
use Socket qw(AF_INET inet_pton);
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
our @EXPORT_OK = qw(packet valid_reply classify_reply query summarize now);
sub now { clock_gettime(CLOCK_MONOTONIC) }
sub packet {
    my ($id,$name) = @_;
    $id =~ /\A\d+\z/ && $id <= 65535 && $name =~ /\A(?:[a-z0-9-]{1,63}\.)*bench\.test\.\z/ && length($name) <= 253 or die "invalid fixture query\n";
    return pack('n6',$id,0x0100,1,0,0,0) . join('',map {pack('C',length($_)).$_} split /\./,$name) . "\0" . pack('n2',1,1);
}
sub valid_reply {
    my ($reply,$request) = @_;
    return 0 if length($reply)<12;
    my ($id,$flags,$qd,$an)=unpack('n4',$reply);
    return 0 unless $id == unpack('n',$request) && ($flags & 0xfa0f)==0x8000 && $qd==1 && $an==1;
    my $question = substr($request,12);
    return 0 unless substr($reply,12,length($question)) eq $question;
    my $off=12+length($question);
    # Accept compressed name pointing to original question or a full owner name.
    if (substr($reply,$off,2) eq "\xc0\x0c") { $off+=2; }
    elsif (substr($reply,$off,length($question)-4) eq substr($question,0,-4)) { $off+=length($question)-4; }
    else { return 0; }
    return 0 if length($reply)<$off+14;
    my ($type,$class,$ttl,$len)=unpack('nnNn',substr($reply,$off,10));
    return $type==1 && $class==1 && $len==4 && substr($reply,$off+10,4) eq pack('C4',192,0,2,80);
}
# Classify errors only after matching the response to the sent question.
sub classify_reply {
    my ($reply,$request)=@_;
    return 'ok' if valid_reply($reply,$request);
    return 'invalid_reply' if length($reply)<12;
    my ($id,$flags,$qd)=unpack('n3',$reply);
    return 'invalid_reply' unless $id==unpack('n',$request) && ($flags & 0xf800)==0x8000 && $qd==1 && substr($reply,12,length($request)-12) eq substr($request,12);
    return 'truncated_reply' if $flags & 0x0200;
    my $rcode=$flags & 15;
    return $rcode ? "rcode_$rcode" : 'invalid_reply';
}
sub read_exact {
    my ($socket,$size,$deadline)=@_;
    my $out='';
    my $sel=IO::Select->new($socket);
    while (length($out)<$size) {
        my $left=$deadline-now();
        return (undef,'timeout') if $left<=0 || !$sel->can_read($left);
        my $n=sysread($socket,my $buf,$size-length($out));
        return (undef,'read_error') unless defined $n;
        return (undef,'peer_closed') unless $n;
        $out.=$buf;
    }
    return ($out,undef);
}
sub query {
    my ($port,$protocol,$name,$timeout,$address,$persistent)=@_;
    $address //= '127.0.0.1';
    $address =~ /\A[0-9.]+\z/ && inet_pton(AF_INET,$address) or die "invalid numeric IPv4 endpoint\n";
    $port =~ /\A\d+\z/ && $port>0 && $port<=65535 && $protocol =~ /\A(?:udp|tcp)\z/ or die "invalid endpoint\n";
    !defined($persistent) || (ref($persistent) =~ /\A(?:SCALAR|REF)\z/ && $protocol eq 'tcp') or die "invalid persistent socket\n";
    my $request=packet(int(rand(65536)),$name);
    my $start=now();
    my $socket=$persistent && $$persistent ? $$persistent : IO::Socket::INET->new(PeerAddr=>$address,PeerPort=>$port,Proto=>$protocol,Timeout=>$timeout);
    return ('connect_error',1000*(now()-$start),0) unless $socket;
    local $SIG{PIPE}='IGNORE';
    my $deadline=$start+$timeout;
    my $wire=$protocol eq 'tcp' ? pack('n',length($request)).$request : $request;
    my $written=syswrite($socket,$wire);
    unless (defined($written) && $written==length($wire)) {
        close $socket; $$persistent=undef if $persistent;
        return ('write_error',1000*(now()-$start),0);
    }
    my ($reply,$error);
    if ($protocol eq 'tcp') {
        my $header;
        ($header,$error)=read_exact($socket,2,$deadline);
        ($reply,$error)=read_exact($socket,unpack('n',$header),$deadline) if defined $header;
    } else {
        my $left=$deadline-now();
        if ($left>0 && IO::Select->new($socket)->can_read($left)) {
            my $peer = recv($socket,$reply,65535,0);
            if (!defined $peer) { $reply=undef; $error='read_error'; }
        } else { $error='timeout'; }
    }
    my $result=!defined($reply) ? ($error//'read_error') : classify_reply($reply,$request);
    if ($persistent && $result eq 'ok') {$$persistent=$socket;}
    else {close $socket; $$persistent=undef if $persistent;}
    return ($result,1000*(now()-$start),1);
}
sub summarize {
    my ($rows,$seconds,$requested)=@_;
    my %counts;
    my @values=sort {$a<=>$b} map {$_->[1]} grep {$_->[0] eq 'ok'} @$rows;
    $counts{$_->[0]}++ for @$rows;
    my $n=@values;
    my $sum=0; $sum+=$_ for @values;
    my $attempted=scalar @$rows;
    my $sent=grep {defined($_->[2]) ? $_->[2] : $_->[0] !~ /\A(?:connect_error|write_error)\z/} @$rows;
    my %r=(requested=>$requested, attempted=>$attempted, sent=>$sent, not_attempted=>$requested-$attempted, failed=>$attempted-$n, successes=>$n, outcomes=>\%counts, seconds=>$seconds, successful_qps=>$seconds>0?$n/$seconds:0);
    $r{latency_ms}={min=>$values[0],mean=>$sum/$n,median=>$n%2?$values[int($n/2)]:($values[$n/2-1]+$values[$n/2])/2,p95=>$values[int(($n*95+99)/100)-1],p99=>$values[int(($n*99+99)/100)-1],max=>$values[-1]} if $n;
    return \%r;
}
1;

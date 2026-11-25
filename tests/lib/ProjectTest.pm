package ProjectTest;
use v5.26;
use strict;
use warnings;
use Exporter 'import';
use File::Temp qw(tempfile);
use POSIX qw(:sys_wait_h setpgid);
use Time::HiRes qw(time sleep);
our @EXPORT_OK = qw(read_bytes write_bytes run_command confirm_command);

sub read_bytes {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "open $path: $!";
    local $/;
    my $data = <$fh> // '';
    close $fh or die "close $path: $!";
    return $data;
}

sub write_bytes {
    my ($path, $data) = @_;
    open my $fh, '>:raw', $path or die "open $path: $!";
    print {$fh} $data or die "write $path: $!";
    close $fh or die "close $path: $!";
}

# Capture child output without pipe deadlocks; no shell argument interpolation.
sub run_command {
    my ($argv, $input, $timeout) = @_;
    $timeout //= 180;
    my ($in) = tempfile(UNLINK => 1);
    my ($out) = tempfile(UNLINK => 1);
    my ($err) = tempfile(UNLINK => 1);
    print {$in} ($input // '') or die "write input: $!";
    seek $in, 0, 0 or die "seek input: $!";
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if (!$pid) {
        setpgid(0, 0) == 0 or POSIX::_exit(126);
        open STDIN, '<&', $in or POSIX::_exit(126);
        open STDOUT, '>&', $out or POSIX::_exit(126);
        open STDERR, '>&', $err or POSIX::_exit(126);
        exec { $argv->[0] } @$argv or POSIX::_exit(127);
    }
    my $deadline = time + $timeout;
    my $status;
    while (1) {
        my $result = waitpid($pid, WNOHANG);
        if ($result == $pid) { $status = $?; last; }
        die "waitpid: $!" if $result == -1;
        if (time >= $deadline) {
            kill 'KILL', -$pid;
            kill 'KILL', $pid;
            waitpid($pid, 0);
            die "command timed out: $argv->[0]";
        }
        sleep 0.02;
    }
    seek $out, 0, 0 or die "seek output: $!";
    seek $err, 0, 0 or die "seek error: $!";
    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$err> // '';
    return { code => ($status & 127) ? 128 + ($status & 127) : $status >> 8,
        stdout => $stdout, stderr => $stderr };
}

# BSD/macOS and util-linux script provide a PTY without a CPAN dependency.
# An explicit child status marker avoids depending on BSD script's exit status.
sub confirm_command {
    my ($script, $operation, $word) = @_;
    local $ENV{STATE_TEST_SCRIPT} = $script;
    local $ENV{STATE_TEST_OPERATION} = $operation;
    my $command = '"$STATE_TEST_SCRIPT" "$STATE_TEST_OPERATION"; rc=$?; printf "\\nSTATE_TEST_EXIT=%s\\n" "$rc"; exit "$rc"';
    my @argv = $^O eq 'darwin'
        ? ('script', '-q', '/dev/null', '/bin/sh', '-c', $command)
        : ('script', '-q', '-e', '-c', $command, '/dev/null');
    my $result = run_command(\@argv, "$word\n", 150);
    my $output = $result->{stdout};
    die "missing confirmation prompt: $output $result->{stderr}" unless $output =~ /to continue:/;
    die "missing child exit status: $output $result->{stderr}" unless $output =~ /STATE_TEST_EXIT=(\d+)\r?\n/;
    $result->{code} = 0 + $1;
    return $result;
}

1;

package ProjectTest;
use v5.26;
use strict;
use warnings;
use Exporter 'import';
use File::Temp qw(tempfile);
use IO::Select;
use POSIX qw(:sys_wait_h setpgid);
use Time::HiRes qw(time sleep clock_gettime CLOCK_MONOTONIC);
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
    my ($argv, $input, $timeout, $watchdog) = @_;
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
    my $deadline = clock_gettime(CLOCK_MONOTONIC) + $timeout;
    my ($status,$reaped);
    my $next_watchdog = clock_gettime(CLOCK_MONOTONIC);
    my $ok = eval {
        while (1) {
            my $result = waitpid($pid, WNOHANG);
            if ($result == $pid) { $status = $?; $reaped=1; last; }
            if ($result == -1) { next if $!{EINTR}; die "waitpid: $!"; }
            if ($watchdog && clock_gettime(CLOCK_MONOTONIC) >= $next_watchdog) {
                $watchdog->();
                $next_watchdog = clock_gettime(CLOCK_MONOTONIC) + 1;
            }
            die "command timed out: $argv->[0]" if clock_gettime(CLOCK_MONOTONIC) >= $deadline;
            sleep 0.02;
        }
        1;
    };
    if (!$ok) {
        my $error=$@ || 'command interrupted';
        if (!$reaped) {
            kill 'KILL', -$pid;
            kill 'KILL', $pid;
            waitpid($pid, 0);
        }
        die $error;
    }
    seek $out, 0, 0 or die "seek output: $!";
    seek $err, 0, 0 or die "seek error: $!";
    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$err> // '';
    return { code => ($status & 127) ? 128 + ($status & 127) : $status >> 8,
        stdout => $stdout, stderr => $stderr };
}

# Wait for the actual prompt before sending input, and leave the input pipe
# open until the PTY child exits. BSD script can discard early input or end
# the input session on EOF before the application reads its confirmation.
sub run_prompt_command {
    my ($argv, $input, $timeout) = @_;
    pipe(my $child_in, my $parent_in) or die "pipe: $!";
    pipe(my $parent_out, my $child_out) or die "pipe: $!";
    pipe(my $parent_err, my $child_err) or die "pipe: $!";
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if (!$pid) {
        setpgid(0, 0) == 0 or POSIX::_exit(126);
        close $parent_in;
        close $parent_out;
        close $parent_err;
        open STDIN, '<&', $child_in or POSIX::_exit(126);
        open STDOUT, '>&', $child_out or POSIX::_exit(126);
        open STDERR, '>&', $child_err or POSIX::_exit(126);
        close $child_in;
        close $child_out;
        close $child_err;
        exec { $argv->[0] } @$argv or POSIX::_exit(127);
    }
    close $child_in;
    close $child_out;
    close $child_err;
    my $select = IO::Select->new($parent_out, $parent_err);
    my $out_fd = fileno($parent_out);
    my ($stdout, $stderr, $sent, $status) = ('', '', 0, undef);
    my $deadline = time + $timeout;
    my $ok = eval {
        local $SIG{PIPE} = 'IGNORE';
        while ($select->count || !defined $status) {
            die "confirmation command timed out: $stdout $stderr" if time >= $deadline;
            for my $fh ($select->can_read(0.05)) {
                my $size = sysread($fh, my $chunk, 8192);
                if (!defined $size) {
                    next if $!{EINTR};
                    die "read confirmation output: $!";
                }
                if (!$size) {
                    $select->remove($fh);
                    close $fh;
                    next;
                }
                if (fileno($fh) == $out_fd) { $stdout .= $chunk; }
                else { $stderr .= $chunk; }
                if (!$sent && $stdout =~ /to continue: /) {
                    my $written = syswrite($parent_in, $input);
                    die "write confirmation: $!" unless defined $written && $written == length $input;
                    $sent = 1;
                }
            }
            if (!defined $status) {
                my $result = waitpid($pid, WNOHANG);
                if ($result == $pid) { $status = $?; }
                elsif ($result == -1 && !$!{EINTR}) { die "waitpid: $!"; }
            }
            sleep 0.02 unless $select->count;
        }
        die "confirmation was not sent: $stdout $stderr" unless $sent;
        1;
    };
    my $error = $@;
    close $parent_in;
    if (!$ok) {
        kill 'KILL', -$pid;
        if (!defined $status) {
            kill 'KILL', $pid;
            waitpid($pid, 0);
        }
        die $error;
    }
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
    my $result = run_prompt_command(\@argv, "$word\n", 150);
    my $output = $result->{stdout};
    die "missing confirmation prompt: $output $result->{stderr}" unless $output =~ /to continue:/;
    die "missing child exit status: $output $result->{stderr}" unless $output =~ /STATE_TEST_EXIT=(\d+)\r?\n/;
    $result->{code} = 0 + $1;
    return $result;
}

1;

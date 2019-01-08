package Open311::Endpoint::Logger;

use Moo;
use DateTime;
use Data::Dumper;
use Log::Dispatch;
with 'Role::Config';

my $add_datetime = sub {
    my %p = @_;
    return sprintf("[%s] %s %s", DateTime->now(), $p{level}, $p{message});
};

has logger => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        return undef unless $self->config->{logfile};
        my $min_level = $self->config->{min_log_level} || 'error';
        Log::Dispatch->new(
            outputs => [
                [ 'File::Locked',
                    min_level => $min_level,
                    filename => $self->config->{logfile},
                    callbacks => $add_datetime,
                    newline => 1,
                    mode => 'append',
                ],
            ]
        );
    }
);

sub log {
    my ($self, $level, $msg) = @_;

    return unless $self->logger;

    $self->logger->$level($msg);
}

sub emergency {
    shift->log('emergency', @_);
}

sub alert {
    shift->log('alert', @_);
}

sub critical {
    shift->log('critical', @_);
}

sub error {
    shift->log('error', @_);
}

sub warn {
    shift->log('warn', @_);
}

sub notice {
    shift->log('notice', @_);
}

sub info {
    shift->log('info', @_);
}

sub debug {
    shift->log('debug', @_);
}

sub dump {
    my ($self, $thing, $msg) = @_;

    $msg = defined $msg ? "$msg: " : '';

    return unless $self->config->{log_dump_calls};

    $self->log('debug', $msg . Dumper($thing));
}

1;

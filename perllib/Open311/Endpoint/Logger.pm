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

BEGIN {
    no strict 'refs';
    my @levels = qw(emergency alert critical error warn notice info debug);
    foreach my $level (@levels) {
        *$level = sub {
            shift->log($level, @_);
        };
    }
}

sub dump {
    my ($self, $thing, $msg) = @_;

    $msg = defined $msg ? "$msg: " : '';

    return unless $self->config->{log_dump_calls};

    $self->log('debug', $msg . Dumper($thing));
}

1;

package Open311::Endpoint::Integration::UK::Bexley;

# use SOAP::Lite +trace => [ qw/method debug/ ];

use Moo;
extends 'Open311::Endpoint::Integration::Symology';

has jurisdiction_id => (
    is => 'ro',
    default => 'bexley',
);

use Integrations::Symology::Bexley;

has integration_class => (
    is => 'ro',
    default => 'Integrations::Symology::Bexley'
);

sub process_service_request_args {
    my $self = shift;
    my @args = $self->SUPER::process_service_request_args(@_);
    my $request = $args[0];

    my $lookup = $self->endpoint_config->{nsgref_to_action};
    $request->{NextAction} = $lookup->{$request->{NSGRef} || ''} || 'S6';

    return @args;
}

1;

package Open311::Endpoint::Integration::UK::CentralBedfordshire;

# use SOAP::Lite +trace => [ qw/method debug/ ];

use Moo;
extends 'Open311::Endpoint::Integration::Symology';

has jurisdiction_id => (
    is => 'ro',
    default => 'centralbedfordshire_symology',
);

# Updates from FMS should always have a GN11 code, meaning "Customer called"
sub event_action_event_type { 'GN11'}

sub process_service_request_args {
    my $self = shift;

    my $area_code = (delete $_[0]->{attributes}->{area_code}) || '';
    my @args = $self->SUPER::process_service_request_args(@_);
    my $response = $args[0];

    my $lookup = $self->endpoint_config->{area_to_username};
    $response->{NextActionUserName} ||= $lookup->{$area_code};

    return @args;
}

1;

package Open311::Endpoint::Integration::UK::Camden;

# use SOAP::Lite +trace => [ qw/method debug/ ];

use Moo;
extends 'Open311::Endpoint::Integration::Symology';

use Open311::Endpoint::Service::UKCouncil::Symology;

has jurisdiction_id => (
    is => 'ro',
    default => 'camden_symology',
);

# Updates from FMS should always have a GN11 code, meaning "Customer called"
sub event_action_event_type { 'NOTE' }

=head2 process_service_request_args

Camden's Symology has got a field for a photo URL, so we we send the first
photo URL to that field when creating a report.

=cut

sub process_service_request_args {
    my $self = shift;

    my @args = $self->SUPER::process_service_request_args(@_);

    # Send the first photo to the appropriate field in Symology
    if ( my $photo_url = $_[0]->{media_url}->[0] ) {
        $args[2] = [
            [ FieldLine => 10, ValueType => 8, DataValue => $photo_url ],
        ];
    }

    return @args;
}

1;

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

Camden's Symology has got three fields for photo URLs. We send the first
three photo URLs to those fields when creating a report.

=cut

sub process_service_request_args {
    my $self = shift;

    my @args = $self->SUPER::process_service_request_args(@_);

    # Add the photo URLs to the request
    my $field_line_value = 10;
    foreach my $photo_url ( @{ $_[0]->{media_url} } ) {
        push @{ $args[2] }, [ FieldLine => $field_line_value, ValueType => 8, DataValue => $photo_url ];

        # Only send the first three photos
        last if $field_line_value == 12;

        $field_line_value++;
    }

    return @args;
}

1;

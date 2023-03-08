package Open311::Endpoint::Integration::UK::CentralBedfordshire;

# use SOAP::Lite +trace => [ qw/method debug/ ];

use Moo;
extends 'Open311::Endpoint::Integration::Symology';

use Open311::Endpoint::Service::UKCouncil::Symology::CentralBedfordshire;

has jurisdiction_id => (
    is => 'ro',
    default => 'centralbedfordshire_symology',
);

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Symology::CentralBedfordshire'
);

# Updates from FMS should always have a GN11 code, meaning "Customer called"
sub event_action_event_type { 'GN11'}

sub process_service_request_args {
    my $self = shift;

    my $location = (delete $_[0]->{attributes}->{title}) || '';
    delete $_[0]->{attributes}->{description};
    delete $_[0]->{attributes}->{report_url};

    my $area_code = (delete $_[0]->{attributes}->{area_code}) || '';
    my @args = $self->SUPER::process_service_request_args(@_);
    my $response = $args[0];

    my $lookup = $self->endpoint_config->{area_to_username};
    $response->{NextActionUserName} ||= $lookup->{$area_code};

    $response->{Location} = $location;

    # Send the first photo to the appropriate field in Symology
    # (these values are specific to Central Beds and were divined by
    # inspecting the GetRequestAdditionalGroup output for an existing
    # enquiry that had a photo.)
    if ( my $photo_url = $_[0]->{media_url}->[0] ) {
        $args[2] = [
            [ FieldLine => 15, ValueType => 8, DataValue => $photo_url ],
        ];
    }

    return @args;
}

# Unlike Bexley, the CSV from the SFTP doesn't have everything we need to
# build the ServiceRequestUpdates. We can get the full picture from the
# Symology API by calling the GetRequestAdditionalGroup method for each
# enquiry mentioned in the CSVs and looking at the history entries there.
sub post_process_files {
    my ($self, $updates) = @_;

    my @updates;
    push(@updates, @{ $self->_updates_for_crno($_) }) for @$updates;

    @$updates = @updates;
}

sub _process_csv_row {
    my ($self, $row, $dt) = @_;
    return ($row->{CRNo}, $row->{CRNo});
}

sub _updates_for_crno {
    my ($self, $crno) = @_;

    my $response = $self->get_integration->get_request(
        "SERV",
        $crno
    );

    if (($response->{StatusCode}//-1) != 0) {
        my $error = $response->{StatusMessage};
        $self->logger->warn("Couldn't call GetRequestAdditionalGroup for CRNo $crno: $error");
        return [];
    }

    return $self->_process_request_history($response, 'full');
}

1;

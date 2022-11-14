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

    return @args;
}

sub _get_csvs {
    my $self = shift;

    my $dir = $self->endpoint_config->{updates_sftp}->{out};
    my @files = glob "$dir/*.CSV";
    return \@files;
}

sub _update_description {
    my ($self, $event) = @_;

    # return join " :: ", $event->{HistoryType}, $event->{HistoryEventType}, $event->{HistoryEventDescription}, $event->{HistoryEvent}, $event->{HistoryReference}, $event->{HistoryDescription};
    # XXX Should this happen for all events or only certain types?
    return $event->{HistoryDescription};
}

sub _update_status {
    my ($self, $event) = @_;

    my $map = $self->endpoint_config->{event_status_mapping}->{$event->{HistoryType}};
    return unless $map;
    return ( $map, $event->{HistoryType} ) unless ref $map eq 'HASH';
    my $field = $map->{field};
    my $external_status = $event->{HistoryType} . "_" . $event->{$field};
    $map = $map->{values};
    return ( $map->{$event->{$field}}, $external_status );
}

# Unlike Bexley, the CSV from the SFTP doesn't have everything we need to
# build the ServiceRequestUpdates. We can get the full picture from the
# Symology API by calling the GetRequestAdditionalGroup method for each
# enquiry mentioned in the CSVs and looking at the history entries there.
sub post_process_csvs {
    my ($self, $updates, $start_time, $end_time) = @_;

    my @updates;
    push(@updates, @{ $self->_updates_for_crno($_, $start_time, $end_time) }) for @$updates;

    @$updates = @updates;
}

sub _process_csv_row {
    my ($self, $row, $dt) = @_;
    return ($row->{CRNo}, $row->{CRNo});
}

sub _updates_for_crno {
    my ($self, $crno, $start, $end) = @_;

    my $response = $self->get_integration->get_request(
        "SERV",
        $crno
    );

    if (($response->{StatusCode}//-1) != 0) {
        my $error = $response->{StatusMessage};
        $self->logger->warn("Couldn't call GetRequestAdditionalGroup for CRNo $crno: $error");
        return [];
    }

    my $history = $response->{Request}->{EventHistory}->{EventHistoryGet};
    my @updates;
    my $w3c = DateTime::Format::W3CDTF->new;
    for my $event (@$history) {
        # The event datetime is stored in two fields - both of which are datetimes
        # but HistoryTime has today's date and HistoryDate has a midnight timestamp.
        # So we need to reconstruct it.
        my $date = $w3c->parse_datetime($event->{HistoryDate});
        my $time = $w3c->parse_datetime($event->{HistoryTime});
        $date->set(hour => $time->hour, minute => $time->minute, second => $time->second);
        $date->set_time_zone("Europe/London");
        next unless $date >= $start && $date <= $end;

        my $update_id = $crno . '_' . $event->{LineNo};
        my $update = $self->_create_update_object($event, $crno, $date, $update_id);
        next unless $update;
        push @updates, $update;
    }

    return \@updates;
}

1;

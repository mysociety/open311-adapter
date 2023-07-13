package Open311::Endpoint::Integration::UK::CentralBedfordshire::Jadu;

=head1 NAME

Open311::Endpoint::Integration::UK::CentralBedfordshire::Jadu -
A Jadu integration specifically for Central Bedfordshire's Fly Tipping service.

=head1 SYNOPSIS

This integration provides a 'Fly Tipping' service.
Posted service requests have cases created in Jadu.
FMS relevant case status changes in Jadu are returned as service request updates.
Posted updates are not sent to Jadu.

=cut

use v5.14;
use warnings;

use Moo;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::EndpointConfig';
with 'Role::Logger';

use DateTime::Format::ISO8601;
use DateTime::Format::W3CDTF;
use Fcntl qw(:flock);
use File::Temp qw(tempfile);
use Geocode::SinglePoint;
use Integrations::Jadu;
use JSON::MaybeXS qw(decode_json encode_json);
use LWP::Simple;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::UKCouncil::CentralBedfordshireFlytipping;
use Open311::Endpoint::Service::Request::Update::mySociety;
use Path::Tiny;
use Try::Tiny;

=head1 CONFIGURATION

=cut

has jurisdiction_id => (
    is => 'ro',
    default => 'centralbedfordshire_jadu',
);

has singlepoint => (
    is => 'lazy',
    default => sub { Geocode::SinglePoint->new(config_filename => $_[0]->jurisdiction_id) }
);

has jadu => (
    is => 'lazy',
    default => sub { Integrations::Jadu->new(config_filename => $_[0]->jurisdiction_id) }
);

has flytipping_service => (
    is => 'lazy',
    default => sub {
        Open311::Endpoint::Service::UKCouncil::CentralBedfordshireFlytipping->new(
            # TODO: Will be renamed to just "Fly Tipping" when ready to replace existing category.
            service_name => "Fly Tipping (Jadu)",
            group => "Flytipping, Bins and Graffiti",
            service_code => "fly-tipping",
            description => "Fly Tipping",
        );
    }
);

sub get_integration {
    return $_[0]->jadu;
}

=head2 reverse_geocode_radius_meters

This is the radius in meters of the area around the report location to search for addresses.

=cut

has reverse_geocode_radius_meters => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{reverse_geocode_radius_meters} }
);

=head2 sys_channel

This is the value to set for the 'sys-channel' field when creating a new Fly Tipping case.

=cut

has sys_channel => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{sys_channel} }
);

=head2 case_type

This is the name of the type of case to use when creating a new Fly Tipping case.

=cut

has case_type => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{case_type} }
);

=head2 town_to_officer

This is a mapping from any town associated with an address in Central Bedfordshire to
the value that should be set in the 'eso-officer' field when creating a new Fly Tipping case.
Towns must be specified in lowercase.

=cut

has town_to_officer => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{town_to_officer} }
);

=head2 most_recently_updated_cases_filter

This is the name of a filter in Jadu that has been configured to return the most recently
updated Fly Tipping cases.

=cut

has most_recently_updated_cases_filter => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{most_recently_updated_cases_filter} }
);

=head2 case_status_to_fms_status

This is a mapping from Jadu Fly Tipping case status labels to a corresponding status in FMS.

=cut

has case_status_to_fms_status => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{case_status_to_fms_status} }
);

=head2 case_status_to_fms_status_timed

Similiar to C<case_status_to_fms_status> but additionally specifies a number of days to wait
before the FMS status is transitioned.
Maps from the Jadu case status to a mapping including 'fms_status' and 'days_to_wait'.

=cut

has case_status_to_fms_status_timed => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{case_status_to_fms_status_timed} }
);

=head2 case_status_tracking_file

The path to a file used by C<gather_updates> to track current case statuses.

=cut

has case_status_tracking_file => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{case_status_tracking_file}  }
);

=head2 update_storage_file

The path to a file containing a sorted JSON list of updates, maintained by C<gather_updates> and consumed by C<get_service_request_updates>.

=cut

has update_storage_file => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{update_storage_file}  }
);

=head2 case_status_tracking_max_age_days

The maximum age of a case to track status updates for. Used by C<gather_updates>.

=cut

has case_status_tracking_max_age_days => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{case_status_tracking_max_age_days}  }
);

=head2 update_storage_max_age_days

The maximum age of an update to to keep in C<update_storage_file>. Used by C<gather_updates>.

=cut

has update_storage_max_age_days => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{update_storage_max_age_days}  }
);


=head1 DESCRIPTION

=cut

sub services {
    my $self = shift;
    return ($self->flytipping_service,);
}

=head2 post_service_request

A new Fly Tipping case is created using C<case_type>.
The town is looked up in C<town_to_officer> to determine which value to set for the 'eso-officer' field.
Files provided as uploads or URLs are added as attachments to the created case.

=cut

sub post_service_request {
    my ($self, $service, $args) = @_;
    my $attributes = $args->{attributes};

    my $addresses = $self->singlepoint->get_nearest_addresses(
        $attributes->{easting},
        $attributes->{northing},
        $self->reverse_geocode_radius_meters,
        ['STREET', 'TOWN', 'USRN'],
    );

    if ($addresses == 0) {
        die sprintf(
            "No addresses found within %dm of easting: %d northing: %d",
            $self->reverse_geocode_radius_meters,
            $attributes->{easting},
            $attributes->{northing},
        );
    }

    my $officer;
    my $nearest_valid_address;
    foreach my $address (@$addresses) {
        my $usrn = $address->{USRN};
        my $street = $address->{STREET};
        my $town = $address->{TOWN};

        unless ($usrn && $street && $town) {
            $self->logger->warn("Skipping address missing one or more of USRN, STREET and TOWN");
            next;
        }

        $officer = $self->town_to_officer->{lc $town};
        if (!$officer) {
            $self->logger->warn("Skipping address with unmapped town: " . $town);
            next;
        }
        $nearest_valid_address = $address;
        last;
    }

    if (!$nearest_valid_address) {
        die "None of the addresses found were valid.";
    }

    my $google_street_view_url = sprintf(
        "https://google.com/maps/@?api=1&map_action=pano&viewpoint=%s,%s",
        $args->{lat}, $args->{long}
    );

    my $type_of_waste = $attributes->{type_of_waste};
    if (ref $type_of_waste eq 'ARRAY') {
        $type_of_waste = join ",", @$type_of_waste;
    }

    my $fly_tip_datetime = DateTime::Format::ISO8601->parse_datetime($attributes->{fly_tip_date_and_time}) if $attributes->{fly_tip_date_and_time};

    my %payload = (
        'coordinates' => $args->{lat} . ',' . $args->{long},
        'ens-latitude' => $args->{lat},
        'ens-longitude' => $args->{long},
        'ens-google-street-view-url' => $google_street_view_url,
        'usrn' => $nearest_valid_address->{USRN},
        'ens-street' => $nearest_valid_address->{STREET},
        'sys-town' => $nearest_valid_address->{TOWN},
        'eso-officer' => $officer,
        'ens-location-description' => $attributes->{title},
        'ens-land-type' => $attributes->{land_type},
        'ens-type-of-waste-fly-tipped' => $type_of_waste,
        'ens-description-of-fly-tipped-waste' => $attributes->{description},
        'ens-fly-tip-witnessed' => $attributes->{fly_tip_witnessed},
        'ens-description-of-alleged-offender' => $attributes->{description_of_alleged_offender},
        'sys-first-name' => $args->{first_name},
        'sys-last-name' => $args->{last_name},
        'sys-email-address' => $args->{email},
        'sys-telephone-number' => $args->{phone},
        'fms-reference' => $attributes->{report_url},
        'sys-channel' => $self->sys_channel
    );
    $payload{'ens-fly-tip-date'} = $fly_tip_datetime->ymd if $fly_tip_datetime;
    $payload{'ens-fly-tip-time'} = $fly_tip_datetime->strftime('%H:%M') if $fly_tip_datetime;

    my $case_reference = $self->jadu->create_case_and_get_reference($self->case_type, \%payload);

    foreach my $url (@{$args->{media_url}}) {

        # Capture file extension from URL.
        $url =~ /(\.\w+)(?:\?.*)?$/;
        my $file_ext = $1;

        my (undef, $tmp_file) = tempfile( SUFFIX => $file_ext );

        my $code = getstore($url, $tmp_file);

        if ($code != 200) {
            $self->logger->warn("Unable to download file from " . $url . " with code " . $code . ".");
            next;
        }

        try {
            $self->jadu->attach_file_to_case($self->case_type, $case_reference, $tmp_file, $url);
        } catch {
            $self->logger->warn("Failed to attach file from " . $url . " to case.");
        }
    }

    foreach my $file (@{$args->{uploads}}) {
        try {
            $self->jadu->attach_file_to_case($self->case_type, $case_reference, $file->{tempname}, $file->{filename});
        } catch {
            $self->logger->warn("Failed to attach uploaded file " . $file->{filename} . " to case.");
        }
    }

    return $self->new_request(
        service_request_id => $case_reference
    );
}

sub get_service_requests {
    my ($self, $args) = @_;
    die "uninmplemented";
}

sub get_service_request {
    my ($self, $service_request_id, $args) = @_;
    die "uninmplemented";
}

=head2 post_service_request_update

This is not supported but is implemented as blank to avoid errors when called as part of the Multi integration.

=cut

sub post_service_request_update {}

=head2 init_update_gathering_files

Initialises C<case_status_tracking_file> and C<update_storage_file> ready for use by C<gather_updates>.

=cut

sub init_update_gathering_files {
    my ($self, $start_from) = @_;
    if (-e $self->case_status_tracking_file && ! -z $self->case_status_tracking_file) {
        die $self->case_status_tracking_file . " already exists and is not empty. Aborting.";
    }
    if (-e $self->update_storage_file && ! -z $self->update_storage_file) {
        die $self->update_storage_file . " already exists and is not empty. Aborting.";
    }

    path($self->case_status_tracking_file)->spew_raw(encode_json({
        latest_update_seen_time => $start_from->epoch,
        cases => {}
    }));

    path($self->update_storage_file)->spew_raw('[]');
}

=head2 gather_updates

Uses C<most_recently_updated_cases_filter>, C<case_status_to_fms_status> and state tracking in C<case_status_tracking_file>
to calculate updates to report, which are stored in C<update_storage_file> for consumption by C<get_service_request_updates>.

Also applies C<case_status_to_fms_status_timed> for timed transitions e.g. "closed if in state A for 10 days."

Limits size of tracking files via C<update_storage_max_age_days> and C<case_status_tracking_max_age_days>.

=cut

sub gather_updates {
    my $self = shift;

    # Keeping this lock for whole duration to prevent interleaving runs.
    my $case_status_tracking_fh = path($self->case_status_tracking_file)->openrw_raw({ locked => 1 });
    read $case_status_tracking_fh, my $tracked_case_statuses_raw, -s $case_status_tracking_fh;
    my $tracked_case_statuses = decode_json($tracked_case_statuses_raw);

    my $update_storage_raw = path($self->update_storage_file)->slurp_raw;
    my $updates = decode_json($update_storage_raw);

    my $case_cutoff = DateTime->now->subtract(days => $self->case_status_tracking_max_age_days)->epoch;
    $self->_delete_old_cases($tracked_case_statuses, $case_cutoff);

    my $update_cutoff = DateTime->now->subtract(days => $self->update_storage_max_age_days)->epoch;
    $self->_delete_old_updates($updates, $update_cutoff);

    push @$updates, @{$self->_apply_time_based_transitions($tracked_case_statuses)};
    push @$updates, @{$self->_fetch_and_apply_updated_cases_info($tracked_case_statuses, $case_cutoff)};

    # Descending time.
    @$updates = sort { $b->{time} <=> $a->{time} } @$updates;

    my $new_tracked_case_statuses_raw = encode_json($tracked_case_statuses);
    my $new_updates_storage_raw = encode_json($updates);

    path($self->update_storage_file)->spew_raw($new_updates_storage_raw);

    seek $case_status_tracking_fh, 0, 0;
    truncate $case_status_tracking_fh, 0;
    print $case_status_tracking_fh $new_tracked_case_statuses_raw;
    close $case_status_tracking_fh;
}

sub _delete_old_cases {
    my ($self, $tracked_case_statuses, $cutoff) = @_;
    while (my ($case_reference, $state) = each %{$tracked_case_statuses->{cases}}) {
        if ($state->{created_time} < $cutoff) {
            delete $tracked_case_statuses->{cases}{$case_reference};
        }
    }
}

sub _delete_old_updates {
    my ($self, $updates, $cutoff) = @_;
    @$updates = grep { $_->{time} > $cutoff } @$updates;
}

sub _apply_time_based_transitions {
    my ($self, $tracked_case_statuses) = @_;
    my @updates;

    while (my ($case_reference, $state) = each %{$tracked_case_statuses->{cases}}) {
        my $timed_status_mapping = $self->case_status_to_fms_status_timed->{$state->{jadu_status}};
        if ($timed_status_mapping && $timed_status_mapping->{fms_status} ne $state->{fms_status}) {
            my $cutoff = DateTime->now()->subtract(days => $timed_status_mapping->{days_to_wait})->epoch;
            if ($state->{jadu_status_update_time} < $cutoff) {
                push @updates, {
                    fms_status => $timed_status_mapping->{fms_status},
                    jadu_status => $state->{jadu_status},
                    case_reference => $case_reference,
                    time => $state->{jadu_status_update_time} + 60 * 60 * 24 * $timed_status_mapping->{days_to_wait},
                };
                $state->{fms_status} = $timed_status_mapping->{fms_status};
            }
        }
    }
    return \@updates;
}

sub _fetch_and_apply_updated_cases_info {
    my ($self, $tracked_case_statuses, $cutoff) = @_;

    my @case_summaries_in_descending_time;

    my $new_latest_update_seen_time = $tracked_case_statuses->{latest_update_seen_time};
    my $all_new_updates_seen = 0;
    my $page_number = 1;
    my $page_items = 1;

    # Case summaries are given in descending time order (i.e most recent first).
    # Iterate through these and collect the ones we need to process.
    while (!$all_new_updates_seen && $page_items > 0) {

        my $case_summaries = $self->jadu->get_case_summaries_by_filter($self->case_type, $self->most_recently_updated_cases_filter, $page_number);
        $page_items = $case_summaries->{num_items};

        foreach my $case_summary (@{ $case_summaries->{items} }) {
            my $update_time = DateTime::Format::ISO8601->parse_datetime($case_summary->{updated_at})->epoch;
            if ($update_time < $tracked_case_statuses->{latest_update_seen_time}) {
                $all_new_updates_seen = 1;
                last
            }
            if ($update_time > $new_latest_update_seen_time) {
                $new_latest_update_seen_time = $update_time;
            }
            push @case_summaries_in_descending_time, $case_summary;
        }
        $page_number++;
    }
    $tracked_case_statuses->{latest_update_seen_time} = $new_latest_update_seen_time;

    # Process the collected case summaries in ascending time order (i.e. chronologically).
    my @updates;
    while (my $case_summary = pop @case_summaries_in_descending_time) {
        my $update_time = DateTime::Format::ISO8601->parse_datetime($case_summary->{updated_at})->epoch;
        my $case_created_time = DateTime::Format::ISO8601->parse_datetime($case_summary->{created_at})->epoch;
        next if $case_created_time < $cutoff;

        my $case_reference = $case_summary->{reference};
        my $jadu_status = $case_summary->{status}->{title};
        my $fms_status = $self->case_status_to_fms_status->{$jadu_status};
        my $existing_state = $tracked_case_statuses->{cases}->{$case_reference};

        next if $existing_state && $jadu_status eq $existing_state->{jadu_status};

        if ($fms_status && ($existing_state && $fms_status ne $existing_state->{fms_status} || !$existing_state)) {
            push @updates, {
                fms_status => $fms_status,
                jadu_status => $jadu_status,
                case_reference => $case_reference,
                time => $update_time
            };
        }
        $tracked_case_statuses->{cases}->{$case_reference} = {
            fms_status => $fms_status ? $fms_status : ( $existing_state ? $existing_state->{fms_status} : '' ),
            jadu_status => $jadu_status,
            jadu_status_update_time => $update_time,
            created_time => $case_created_time
        };
    }

    return \@updates;
}

=head2 get_service_request_updates

Reads updates from C<update_storage_file>.

=cut

sub get_service_request_updates {
    my ($self, $args) = @_;
    my $w3c = DateTime::Format::W3CDTF->new;
    my $start_time = $w3c->parse_datetime($args->{start_date})->epoch;
    my $end_time = $w3c->parse_datetime($args->{end_date})->epoch;

    my $update_storage_raw = path($self->update_storage_file)->slurp_raw;
    my $updates = decode_json($update_storage_raw);
    my @updates_to_send;

    foreach my $update (@$updates) {
        next if $update->{time} > $end_time;
        # Assuming in descending time order.
        last if $update->{time} < $start_time;
        my %args = (
            status => $update->{fms_status},
            external_status_code => $update->{jadu_status},
            update_id => $update->{case_reference} . '_' . $update->{time},
            service_request_id => $update->{case_reference},
            description => "",
            updated_datetime => DateTime->from_epoch(epoch => $update->{time}),
        );
        push @updates_to_send, Open311::Endpoint::Service::Request::Update::mySociety->new( %args );
    }
    return @updates_to_send;
}

1;

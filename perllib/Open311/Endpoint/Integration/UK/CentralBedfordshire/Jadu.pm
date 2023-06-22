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

use DateTime::Format::ISO8601;
use DateTime::Format::W3CDTF;
use Integrations::Jadu;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::UKCouncil;
use Open311::Endpoint::Service::Request::Update::mySociety;

=head1 CONFIGURATION

=cut

has jurisdiction_id => (
    is => 'ro',
    default => 'centralbedfordshire_jadu',
);

has integration_class => (
    is => 'ro',
    default => 'Integrations::Jadu'
);

has jadu => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(config_filename => $_[0]->jurisdiction_id) }
);

=head2 sys_channel

This is the value to set for the 'sys-channel' field when creating a new Fly Tipping case.

=cut

has sys_channel => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{jadu_sys_channel} }
);

=head2 case_type

This is the name of the type of case to use when creating a new Fly Tipping case.

=cut

has case_type => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{jadu_case_type} }
);

=head2 most_recently_updated_cases_filter

This is the name of a filter in Jadu that has been configured to return the most recently
updated Fly Tipping cases.

=cut

has most_recently_updated_cases_filter => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{jadu_most_recently_updated_cases_filter} }
);

=head2 jadu_case_status_to_fms_status

This is a mapping of Jadu Fly Tipping case status labels to a corresponding status in FMS.

=cut

has jadu_case_status_to_fms_status => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{jadu_case_status_to_fms_status} }
);

=head2 town_to_officer

This is a mapping from any town associated with an address in Central Bedfordshire to
the value that should be set in the 'eso-officer' field when creating a new Fly Tipping case.

=cut

has town_to_officer => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{town_to_officer} }
);

=head1 DESCRIPTION

=cut

sub services {
    my $fly_tipping_service = Open311::Endpoint::Service::UKCouncil->new(
        # TODO: Will be renamed to just "Fly Tipping" when ready to replace existing category.
        service_name => "Fly Tipping (Jadu)",
        group => "Flytipping, Bins and Graffiti",
        service_code => "fly-tipping",
        description => "Fly Tipping",
    );
    push @{$fly_tipping_service->attributes}, Open311::Endpoint::Service::Attribute->new(
        code => "report_url",
        required => 1,
        datatype => "string",
        description => "Report URL",
        automated => 'server_set'
    );
    push @{$fly_tipping_service->attributes}, Open311::Endpoint::Service::Attribute->new(
        code => "usrn",
        description => "USRN",
        datatype => "string",
        required => 1,
        automated => 'server_set'
    );
    push @{$fly_tipping_service->attributes}, Open311::Endpoint::Service::Attribute->new(
        code => "street",
        description => "Street",
        datatype => "string",
        required => 1,
        automated => 'server_set'
    );
    push @{$fly_tipping_service->attributes}, Open311::Endpoint::Service::Attribute->new(
        code => "town",
        description => "Town",
        datatype => "string",
        required => 1,
        automated => 'server_set'
    );
    push @{$fly_tipping_service->attributes}, Open311::Endpoint::Service::Attribute->new(
        code => "location_description",
        variable => 1,
        required => 1,
        datatype => "text",
        description => "Please provide further details on the exact location, including the closest door number, specific landmark to assist officers"
    );
    push @{$fly_tipping_service->attributes}, Open311::Endpoint::Service::Attribute->new(
        code => "land_type",
        variable => 1,
        required => 1,
        datatype => "singlevaluelist",
        description => "The flytip is located on:",
        "values" => {
            "Roadside / verge" => "Roadside / verge",
            "Footpath" => "Footpath",
            "Private land" => "Private land",
            "Public land" => "Public land",
        }
    );
    push @{$fly_tipping_service->attributes}, Open311::Endpoint::Service::Attribute->new(
        code => "type_of_waste",
        variable => 1,
        required => 1,
        datatype => "multivaluelist",
        description => "What type of waste is it?",
        "values" => {
            "Asbestos" => "Asbestos",
            "Black bags" => "Black bags",
            "Building materials" => "Building materials",
            "Chemical / oil drums" => "Chemical / oil drums",
            "Construction waste" => "Construction waste",
            "Electricals" => "Electricals",
            "Fly posting" => "Fly posting",
            "Furniture" => "Furniture",
            "Green / garden waste" => "Green / garden waste",
            "Household waste / black bin bags" => "Household waste / black bin bags",
            "Mattress or bed base" => "Mattress or bed base",
            "Trolleys" => "Trolleys",
            "Tyres" => "Tyres",
            "Vehicle parts" => "Vehicle parts",
            "White goods - fridge, freezer, washing matchine etc" => "White goods - fridge, freezer, washing matchine etc",
            "Other" => "Other",
        }
    );
    push @{$fly_tipping_service->attributes}, Open311::Endpoint::Service::Attribute->new(
        code => "description_of_waste",
        variable => 1,
        required => 1,
        datatype => "text",
        description => "Please describe the type of waste"
    );
    push @{$fly_tipping_service->attributes}, Open311::Endpoint::Service::Attribute->new(
        code => "fly_tip_witnessed",
        variable => 1,
        required => 1,
        datatype => "singlevaluelist",
        description => "Did you observe this taking place?",
        "values" => {
            "Yes" => "Yes",
            "No" => "No",
        }
    );
    push @{$fly_tipping_service->attributes}, Open311::Endpoint::Service::Attribute->new(
        code => "fly_tip_date_and_time",
        variable => 1,
        # Only required when fly tip witnessed, expecting client to enforce this.
        required => 0,
        datatype => "datetime",
        description => "When did this take place?"
    );
    push @{$fly_tipping_service->attributes}, Open311::Endpoint::Service::Attribute->new(
        code => "description_of_alleged_offender",
        variable => 1,
        # Only required when fly tip witnessed, expecting client to enforce this.
        required => 0,
        datatype => "text",
        description => "Please provde any futher information which may help identify the alleged offender"
    );

    return ($fly_tipping_service,);
}

=head2 post_service_request

A new Fly Tipping case is created using C<case_type>.
The town is looked up in C<town_to_officer> to determine which value to set for the 'eso-officer' field.
Files provided as uploads are added as attachments to the created case.

=cut

sub post_service_request {
    my ($self, $service, $args) = @_;
    my $attributes = $args->{attributes};

    my $officer = $self->town_to_officer->{$attributes->{town}};
    if (!$officer) {
        die "No officer found for town " . $attributes->{town};
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
        'usrn' => $attributes->{usrn},
        'ens-street' => $attributes->{street},
        'sys-town' => $attributes->{town},
        'eso-officer' => 'area_5',
        'ens-location_description' => $attributes->{location_description},
        'ens-land-type' => $attributes->{land_type},
        'ens-type-of-waste-fly-tipped' => $type_of_waste,
        'ens-description-of-fly-tipped-waste' => $attributes->{description_of_waste},
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

    foreach my $file (@{$args->{uploads}}) {
        $self->jadu->attach_file_to_case($self->case_type, $case_reference, $file->{tempname}, $file->{filename});
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

This is not supported but will implement as blank to avoid errors when called as part of the Central Bedfordshire Multi integration.

=cut

sub post_service_request_update {}

=head2 get_service_request_updates

Returns status updates only - no text is retrieved.
The C<most_recently_updated_cases_filter> is used to query for Fly Tipping cases which were last modified within
the given time window.
For each of these, an update is created if there is a mapping found for the Jadu status in C<jadu_case_status_to_fms_status>.

Since updates can be for things other than status changes, there will be superfluous updates where no status change
has actually taken place.
To avoid having to track state in open311-adapter - the client is expected to handle these.

=cut

sub get_service_request_updates {
    my ($self, $args) = @_;
    my $w3c = DateTime::Format::W3CDTF->new;
    my $start_time = $w3c->parse_datetime($args->{start_date});
    my $end_time = $w3c->parse_datetime($args->{end_date});

    my @updates;

    my $page_number = 1;
    my $all_seen = 0;

    while (!$all_seen) {
        my $case_summaries = $self->jadu->get_case_summaries_by_filter($self->case_type, $self->most_recently_updated_cases_filter, $page_number);

        last if $case_summaries->{num_items} == 0;

        foreach my $case_summary (@{ $case_summaries->{items} }) {
            my $updated_at = DateTime::Format::ISO8601->parse_datetime($case_summary->{updated_at});

            next if $updated_at > $end_time;
            if ($updated_at < $start_time) {
                $all_seen = 1;
                last;
            }

            my $jadu_status = $case_summary->{status}->{title};
            my $fms_status = $self->jadu_case_status_to_fms_status->{$jadu_status};

            next if !$fms_status;

            my %args = (
                status => $fms_status,
                external_status_code => $jadu_status,
                update_id => $case_summary->{reference} . '_' . $updated_at->epoch,
                service_request_id => $case_summary->{reference},
                description => "",
                updated_datetime => $updated_at,
            );

            push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new( %args );
        }
        $page_number++;
    }
    return @updates;
}

1;

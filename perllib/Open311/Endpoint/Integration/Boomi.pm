package Open311::Endpoint::Integration::Boomi;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::EndpointConfig';
with 'Role::Logger';

use Encode qw(encode_utf8);
use POSIX qw(strftime);
use MIME::Base64 qw(encode_base64);
use Open311::Endpoint::Service::UKCouncil::Boomi;
use Open311::Endpoint::Service::Request::Update::mySociety;
use Open311::Endpoint::Service::Request::ExtendedStatus;
use Integrations::Surrey::Boomi;
use JSON::MaybeXS;
use DateTime::Format::W3CDTF;
use Path::Tiny;
use Try::Tiny;
use LWP::UserAgent;
use Digest::MD5 qw(md5_hex);

has '+request_class' => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::Request::ExtendedStatus',
);

sub service_request_content {
    '/open311/service_request_extended'
}

has jurisdiction_id => (
    is => 'ro',
    required => 1,
);

has boomi => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(config_filename => $_[0]->jurisdiction_id) }
);

has integration_class => (
    is => 'ro',
    default => 'Integrations::Surrey::Boomi',
);

sub get_integration { $_[0]->boomi }

sub service {
    my ($self, $id, $args) = @_;

    my $service = Open311::Endpoint::Service::UKCouncil::Boomi->new(
        service_name => $id,
        service_code => $id,
        description => $id,
        type => 'realtime',
        keywords => [qw/ /],
        allow_any_attributes => 1,
    );

    return $service;
}


sub services {
    my ($self) = @_;

    # Boomi doesn't provide a list of services; they're just created as
    # contacts in the FMS admin.

    return ();
}

sub post_service_request {
    my ($self, $service, $args) = @_;

    die "Args must be a hashref" unless ref $args eq 'HASH';

    $self->logger->info("[Boomi] Creating issue");
    # $self->logger->debug("[Boomi] POST service request args: " . encode_json($args));

    my @custom_fields = (
        {
            id => 'category',
            values => [ $args->{attributes}->{group} ],
        },
        {
            id => 'subCategory',
            values => [ $args->{attributes}->{category} ],
        },
        {
            id => 'service_code',
            values => [ $args->{service_code} ],
        },
    );

    my $ticket = {
        integrationId => $self->endpoint_config->{integration_ids}->{upsertHighwaysTicket},
        subject => $args->{attributes}->{title},
        status => 'open',
        description => $args->{attributes}->{description},
        location => {
            latitude => $args->{lat},
            longitude => $args->{long},
            easting => $args->{attributes}->{easting},
            northing => $args->{attributes}->{northing},
            usrn => $args->{attributes}->{USRN},
            streetName => $args->{attributes}->{ROADNAME},
            town => $args->{attributes}->{POSTTOWN},
        },
        requester => {
            fullName => $args->{first_name} . " " . $args->{last_name},
            email => $args->{email},
            phone => $args->{phone},
        },
    };

    foreach (qw/group category easting northing title description phone USRN ROADNAME POSTTOWN/) {
        if (defined $args->{attributes}->{$_}) {
            delete $args->{attributes}->{$_};
        }
    }
    for my $attr (sort keys %{ $args->{attributes} }) {
        my $val = $args->{attributes}->{$attr};

        my $name;
        # see if it's a JSON string that encodes a value and a description
        if ($val =~ /^{/) {
            try {
                my $decoded = decode_json($val);
                $val = $decoded->{value} || $val;
                $name = $decoded->{description} || "";
            } catch {
                $self->logger->debug("[Boomi] Couldn't decode JSON from Open311 attribute value: $val");
            };
        }

        push @custom_fields, {
            id => $attr,
            # multivaluelist fields arrive as an arrayref
            values => ref $val eq 'ARRAY' ? $val : [ $val ],
            $name ? ( name => $name) : (),
        };
    }
    $ticket->{customFields} = \@custom_fields;

    $self->_add_attachments($args, $ticket);

    my $service_request_id = $self->boomi->upsertHighwaysTicket($ticket);

    return $self->new_request(
        service_request_id => $service_request_id,
    )
}

sub get_service_requests {
    my ($self, $args) = @_;

    my $integration_ids = $self->endpoint_config->{integration_ids}->{getNewHighwaysTickets};
    return () unless $integration_ids;
    $integration_ids = [ $integration_ids ] unless ref $integration_ids eq 'ARRAY';

    my @requests;
    foreach (@$integration_ids) {
        push @requests, $self->_get_service_requests_for_integration_id($_, $args);
    }
    return @requests;
}


sub _get_service_requests_for_integration_id {
    my ($self, $integration_id, $args) = @_;

    my $start = DateTime::Format::W3CDTF->parse_datetime($args->{start_date});
    my $end = DateTime::Format::W3CDTF->parse_datetime($args->{end_date});

    my $results = $self->boomi->getNewHighwaysTickets($integration_id, $start, $end);

    my @requests;
    for my $result (@$results) {
        my $id = $result->{fmsReport}->{externalId};
        my ($loggedDate, $e, $n) = do {
            if (my $enq = $result->{confirmEnquiry}) {
                ($enq->{loggedDate}, $enq->{easting}, $enq->{northing});
            } else {
                $id = "JOB_" . $id;
                my $job = $result->{confirmJob};
                ($job->{entryDate}, $job->{easting}, $job->{northing});
            }
        };
        $loggedDate = DateTime::Format::W3CDTF->parse_datetime($loggedDate);

        # if any of these is missing then ignore this record.
        next unless $id && $loggedDate && $e && $n;

        my $status = lc $result->{fmsReport}->{status}->{state};
        $status =~ s/ /_/g;
        # fixup invalid status from Boomi
        $status = "not_councils_responsibility" if $status eq "not_responsible";

        my $args = {
            service_request_id => "Zendesk_$id",
            status => $status,
            description => $result->{fmsReport}->{description},
            title => $result->{fmsReport}->{title},
            requested_datetime => $loggedDate,
            updated_datetime => $loggedDate,
            service => Open311::Endpoint::Service->new(
                service_name => $result->{fmsReport}->{title},
                service_code => $result->{fmsReport}->{categorisation}->{serviceId},
            ),
            service_notice => $result->{fmsReport}->{title},
            latlong => [ $n, $e ],
        };
        my $service_request = $self->new_request(%$args);

        push @requests, $service_request;
    }

    return @requests;
}

sub get_service_request_updates {
    my ($self, $args) = @_;

    my $integration_ids = $self->endpoint_config->{integration_ids}->{getHighwaysTicketUpdates};
    return () unless $integration_ids;
    $integration_ids = [ $integration_ids ] unless ref $integration_ids eq 'ARRAY';

    my @updates;
    foreach (@$integration_ids) {
        push @updates, $self->_get_service_request_updates_for_integration_id($_, $args);
    }

    return @updates;
}

sub _get_service_request_updates_for_integration_id {
    my ($self, $integration_id, $args) = @_;

    my $start = DateTime::Format::W3CDTF->parse_datetime($args->{start_date});
    my $end = DateTime::Format::W3CDTF->parse_datetime($args->{end_date});

    my $results = $self->boomi->getHighwaysTicketUpdates($integration_id, $start, $end);
    my $w3c = DateTime::Format::W3CDTF->new;

    my @updates;

    for my $update (@$results) {
        my $enquiry_update = $update->{confirmEnquiryStatusLog} ? 1 : 0;
        my $log = $enquiry_update ? $update->{confirmEnquiryStatusLog} : $update->{confirmJobStatusLog};
        my $fms = $update->{fmsReport};

        my $id = $fms->{externalId} . "_" . $log->{logNumber};
        my $service_request_id = $enquiry_update
            ? "Zendesk_" . $fms->{externalId}
            : "Zendesk_JOB_" . $fms->{externalId};
        my $status = lc $fms->{status}->{state};
        $status =~ s/ /_/g;
        # fixup invalid status from Boomi
        $status = "not_councils_responsibility" if $status eq "not_responsible";

        push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new(
            status => $status,
            update_id => $id,
            service_request_id => $service_request_id,
            description => $fms->{status}->{label},
            updated_datetime => $w3c->parse_datetime( $log->{loggedDate} )->truncate( to => 'second' ),
        );
    }

    return @updates;
}

sub post_service_request_update {
    my ($self, $args) = @_;

    die "Args must be a hashref" unless ref $args eq 'HASH';

    $self->logger->info("[Boomi] Creating update");

    my ($system, $id) = split('_', $args->{service_request_id});

    my $ticket = {
        integrationId => $self->endpoint_config->{integration_ids}->{upsertHighwaysTicket},
        ticketId => $id,
        comments => [
            { body => $args->{description} },
        ],
    };

    $self->_add_attachments($args, $ticket);

    # we don't get back a unique ID from Boomi, so calculate one ourselves
    # XXX is this going to be mirrored back next time we fetch updates?
    my @parts = map { $args->{$_} } qw/service_request_id description update_id updated_datetime/;
    my $hash = substr(md5_hex(encode_utf8(join('', @parts))), 0, 8);
    my $update_id = $args->{service_request_id} . "_" . $hash;

    if ($args->{description}) {
        # State changes on FMS may create updates with empty descriptions, which
        # we don't want to send to Boomi as it will return an error.
        $self->boomi->upsertHighwaysTicket($ticket);
    }

    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        service_request_id => $args->{service_request_id},
        status => lc $args->{status},
        update_id => $update_id,
    );
}

sub _add_attachments {
    my ($self, $args, $ticket) = @_;

    my @attachments;

    for my $photo (@{ $args->{media_url} }) {
        my $filename = (URI->new($photo)->path_segments)[-1];
        push @attachments, {
            url => $photo,
            fileName => $filename,
        };
    }

    if (@{$args->{uploads}}) {
        foreach (@{$args->{uploads}}) {
            push @attachments, {
                fileName => $_->filename,
                base64 => encode_base64(path($_)->slurp),
            };
        }
    }

    $ticket->{attachments} = \@attachments if @attachments;
}

1;

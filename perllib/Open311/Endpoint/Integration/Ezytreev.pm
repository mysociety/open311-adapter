package Open311::Endpoint::Integration::Ezytreev;

use JSON::MaybeXS;
use Path::Tiny;
use YAML::XS qw(LoadFile);
use Digest::MD5 qw(md5_hex);
use DateTime::Format::W3CDTF;

use Integrations::Ezytreev;
use Open311::Endpoint::Service::UKCouncil::Ezytreev;
use Open311::Endpoint::Service::Request::Update::mySociety;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::Logger';

has endpoint_config => ( is => 'lazy' );

sub _build_endpoint_config {
    my $self = shift;
    my $config_file = path(__FILE__)->parent(5)->realpath->child('conf/council-' . $self->jurisdiction_id . '.yml');
    my $conf = LoadFile($config_file);
    return $conf;
}

has jurisdiction_id => (
    is => 'ro',
);

has ezytreev => (
    is => 'lazy',
    default => sub { Integrations::Ezytreev->new(config_filename => $_[0]->jurisdiction_id) }
);

sub get_integration {
    return $_[0]->ezytreev;
}

has category_mapping => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{category_mapping} }
);

has forward_status_mapping => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{forward_status_mapping} }
);

has reverse_status_mapping => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{reverse_status_mapping} }
);

sub services {
    my $self = shift;
    my $services = $self->category_mapping;
    my @services = map {
        my $name = $services->{$_}{name};
        my $service = Open311::Endpoint::Service::UKCouncil::Ezytreev->new(
            service_name => $name,
            service_code => $_,
            description => $name,
            $services->{$_}{group} ? (group => $services->{$_}{group}) : (),
      );
    } sort keys %$services;
    return @services;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    my $crm_xref = "fms:" . $args->{attributes}->{fixmystreet_id};

    my $response = $self->ezytreev->update_enquiry({
        CRMXRef => $crm_xref,
        EnquiryDescription => $args->{description},
        Forename => $args->{first_name},
        Surname => $args->{last_name},
        Category => "T",  # Always T, the actual category goes into EnquiryType below
        EnquiryType => $args->{service_code},
        TelHome => $args->{phone},
        EmailAddress => $args->{email},
        EnquiryOX => $args->{attributes}->{easting},
        EnquiryOY => $args->{attributes}->{northing},
        TreeCodes => $args->{attributes}->{tree_code},
    });
    die "Failed to send report to ezytreev" unless $response->is_success;

    # Enquiry ID is the body of the response
    my $enquiry_id = $response->content;
    $enquiry_id =~ s/^\s+|\s+$//g;

    # Now deal with photos.
    foreach my $media_url (@{$args->{media_url}}) {
        my $response = $self->ezytreev->upload_enquiry_document({
            crm_xref => $crm_xref,
            media_url => $media_url,
        });

        if (!$response->is_success) {
            $self->logger->warn("Error sending photo: $media_url");
            next;
        }
    }

    return $self->new_request(
        service_request_id => "ezytreev-" . $enquiry_id,
    );
}

sub get_service_request_updates {
    my $self = shift;

    my $response = $self->ezytreev->get_enquiry_changes;
    die "Failed to get report updates from ezytreev" unless $response->is_success;

    my @updates;
    my $enquiry_changes = decode_json($response->content);
    my $w3c = DateTime::Format::W3CDTF->new;

    foreach my $enquiry (@$enquiry_changes) {
        # Ignore updates on enquiries that weren't created by FMS
        next unless substr($enquiry->{CRMXRef}, 0, 4) eq 'fms:';
        foreach my $enquiry_status (@{$enquiry->{StatusHistory}}) {
            # Ignore updates created by FMS
            next if $enquiry_status->{StatusByName} eq 'CRM System';
            my $status = $self->reverse_status_mapping->{$enquiry_status->{EnquiryStatusCode}};
            if (!$status) {
                $self->logger->warn("Missing reverse status mapping for EnquiryStatus Code " .
                    "$enquiry_status->{EnquiryStatusCode} (EnquiryStatusID $enquiry_status->{EnquiryStatusID})\n");
                $status = "open";
            }
            my $dt = $w3c->parse_datetime($enquiry_status->{StatusDate});
            my $status_description = $enquiry_status->{EnquiryStatusDescription};
            $status_description =~ s/^\s+|\s+$//g;
            my %update_args = (
                status => $status,
                update_id => "ezytreev-update-" . $enquiry_status->{EnquiryStatusID},
                service_request_id => "ezytreev-" . $enquiry->{EnqRef},
                description => $status_description,
                updated_datetime => $dt,
                external_status_code => $enquiry_status->{EnquiryStatusCode},
            );
            push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new(%update_args);
        }
    }
    return @updates;
}

sub post_service_request_update {
    my ($self, $args) = @_;

    my $crm_xref = "fms:" . $args->{service_request_id_ext};

    my $body = {
        CRMXRef => $crm_xref,
        StatusInfo => $args->{description},
    };

    my $status_code = $self->forward_status_mapping->{$args->{status}};

    if ($status_code) {
        $body->{EnquiryStatusCode} = $status_code;
    } else {
        $self->logger->warn("Missing forward status mapping for $args->{status} " .
            "(service_request_id_ext: $args->{service_request_id_ext})\n");
    }

    my $response = $self->ezytreev->update_enquiry($body);

    die "Failed to send update to ezytreev" unless $response->is_success;

    # Now deal with photos.
    foreach my $media_url (@{$args->{media_url}}) {
        my $response = $self->ezytreev->upload_enquiry_document({
            crm_xref => $crm_xref,
            media_url => $media_url,
        });

        if (!$response->is_success) {
            $self->logger->warn("Error sending photo: $media_url");
            next;
        }
    }

    # Enquiry ID is the body of the response
    my $enquiry_id = $response->content;
    $enquiry_id =~ s/^\s+|\s+$//g;
    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        service_request_id => "ezytreev-" . $enquiry_id,
        status => lc $args->{status},
        update_id => $args->{update_id},
    );
}

__PACKAGE__->run_if_script;

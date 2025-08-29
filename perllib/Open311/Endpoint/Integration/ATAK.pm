package Open311::Endpoint::Integration::ATAK;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::EndpointConfig';
with 'Role::Logger';

use POSIX qw(strftime);
use MIME::Base64 qw(encode_base64);
use Open311::Endpoint::Service::UKCouncil::ATAK;
use Integrations::ATAK;
use JSON::MaybeXS;
use DateTime::Format::W3CDTF;
use Path::Tiny;
use Try::Tiny;
use Encode qw(encode);

has jurisdiction_id => (
    is => 'ro',
    required => 1,
);

sub get_integration {
    my ($self) = @_;

    $self->log_identifier($self->jurisdiction_id);
    my $atak = Integrations::ATAK->new(config_filename => $self->jurisdiction_id);
    return $atak;
}

sub services {
    my ($self) = @_;

    my $services = $self->endpoint_config->{services};
    my @services = map {
        my $name = $services->{$_}{name};
        my $service = Open311::Endpoint::Service::UKCouncil::ATAK->new(
            service_name => $name,
            service_code => $_,
            description => $name,
            $services->{$_}{group} ? (group => $services->{$_}{group}) : (),
            $services->{$_}{groups} ? (groups => $services->{$_}{groups}) : (),
        );
    } sort keys %$services;
    return @services;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;
    die "Args must be a hashref" unless ref $args eq 'HASH';

    $self->logger->info("[ATAK] Creating issue for service " . $service->service_name);

    # Uploads break the json encoding for the debug logs, so popping beforehand.
    my $uploads = delete $args->{uploads};
    $self->logger->debug("[ATAK] POST service request args: " . encode_json($args));

    my @attachments;

    my $image_counter = 1;
    if (@{$uploads}) {
        @attachments = map {
            my $content_type = $_->content_type ? $_->content_type : 'image/jpeg';
            {
                filename => $_->filename,
                description => "Image " . $image_counter++,
                data => "data:" . $content_type . ";base64," . encode_base64(path($_)->slurp)
            }
        } @{$uploads};
    } elsif (@{$args->{media_url}}) {
        @attachments = map {
            my $content_type = $_->content_type ? $_->content_type : 'image/jpeg';
            {
                filename => $_->filename,
                description => "Image " . $image_counter++,
                data => "data:" . $content_type . ";base64," . encode_base64($_->content)
            }
        } $self->_get_attachments($args->{media_url});
    }

    my $issue_text = $self->_format_issue_text(
        $self->endpoint_config->{max_issue_text_bytes},
        $args->{attributes}->{location_name} || '',
        $args->{attributes}->{report_url},
        $args->{attributes}->{title},
        $args->{attributes}->{detail},
    );

    my $issue_title = $args->{attributes}->{group} . '|' . $service->service_name,

    my $now = DateTime->now;
    my $later = $now->clone->add(hours => 1);
    my $time_format = "%Y-%m-%dT%H:%M:%SZ";

    my $issue = {
        request_client_ref => $args->{attributes}->{fixmystreet_id},
        requesttype_desc => 'FixMyStreets',
        request_start_date => $now->strftime($time_format),
        request_end_date => $later->strftime($time_format),
        project_code => $self->endpoint_config->{project_code},
        project_name => $self->endpoint_config->{project_name},
        request_title => $issue_title,
        request_desc => $issue_text,
        location_name => $args->{attributes}->{location_name} || '',
        caller => "",
        resolve_by => "",
        request_geo_ref => {
            type => 'Point',
            coordinates => [
                # Add zero to force numeric context
                $args->{long} + 0,
                $args->{lat} + 0,
            ],
        }
    };

    $self->logger->debug("[ATAK] Issue: " . encode_json($issue));

    if (@attachments) {
        $issue->{attachments} = \@attachments;
    }

    my $service_request_id = $self->get_integration->create_issue($issue);

    return $self->new_request(
        service_request_id => $service_request_id,
    )
}

sub _format_issue_text {
    my ($self, $byte_limit, $location_name, $url, $title, $detail) = @_;

    # Populate everything except the detail field which we may need to truncate.
    my $issue_text = sprintf(
        "Location: %s\n\nlocation of problem: %s\n\ndetail: %%s\n\nurl: %s\n\nSubmitted via FixMyStreet\n",
        $location_name, $title, $url
    );

    # +2 for the not yet used format directive for detail (%s).
    my $max_detail_bytes = $byte_limit - length(encode('UTF-8', $issue_text)) + 2;
    my $detail_bytes = length(encode('UTF-8', $detail));

    # We need at least 3 bytes of leeway so we can use an ellipsis to indicate
    # the detail was truncated.
    # Note using horizontal ellipsis (U+2026) results in an internal server error.
    if ($max_detail_bytes < 3 && $detail_bytes > $max_detail_bytes) {
        die "Issue text is too large, even if we were to truncate the detail before inserting: " . $issue_text;
    }

    if ($detail_bytes > $max_detail_bytes) {
        # In theory we could truncate less for the ellipsis if the trailing characters are multi-byte, but keeping it simple.
        my $characters_to_strip = $detail_bytes - $max_detail_bytes + 3;
        $detail = substr($detail, 0, -$characters_to_strip) . "...";
    }

    return sprintf($issue_text, $detail);

}

sub _get_attachments {
    my ($self, $urls) = @_;

    my @photos = ();
    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    for (@$urls) {
        my $response = $ua->get($_);
        if ($response->is_success) {
            push @photos, $response;
        } else {
            $self->logger->error("[ATAK] Unable to download attachment: " . $_);
            $self->logger->debug("[ATAK] Photo response status: " . $response->status_line);
            $self->logger->debug("[ATAK] Photo response content: " . $response->decoded_content);
        }
    }
    return @photos;
}

=head2 get_service_request_updates

Returns an empty array as we are providing
a web hook for updates

=cut

sub get_service_request_updates {
    return ();
}

sub init_update_gathering_files {
    my ($self, $start_from) = @_;

    my $issue_status_tracking_file = $self->endpoint_config->{issue_status_tracking_file};
    my $update_storage_file = $self->endpoint_config->{update_storage_file};

    if (-e $issue_status_tracking_file && ! -z $issue_status_tracking_file) {
        die $issue_status_tracking_file . " already exists and is not empty. Aborting.";
    }
    if (-e $update_storage_file && ! -z $update_storage_file) {
        die $update_storage_file . " already exists and is not empty. Aborting.";
    }

    path($issue_status_tracking_file)->spew_raw(encode_json({
        latest_update_seen_time => $start_from->epoch,
        issues => {}
    }));

    path($update_storage_file)->spew_raw('[]');
}

1;

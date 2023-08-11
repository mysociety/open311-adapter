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
    $self->logger->debug("[ATAK] POST service request args: " . encode_json($args));

    my @attachments;

    if ($args->{media_url}) {
        my $i = 1;
        @attachments = map {
            my $content_type = $_->content_type ? $_->content_type : 'image/jpeg';
            {
                filename => $_->filename,
                description => "Image " . $i++,
                data => "data:" . $content_type . ";base64," . encode_base64($_->content)
            }
        } $self->_get_attachments($args->{media_url});
    }

    my $issue_template = "Category: %s\nLocation: %s\n\n%s\n";

    my $issue_text = sprintf(
        $issue_template,
        $service->service_name,
        $args->{attributes}->{location_name} || '',
        $args->{description},
    );

    my $issue = {
        client_ref => $args->{attributes}->{fixmystreet_id},
        taken_on => strftime("%Y-%m-%dT%H:%M:%SZ", gmtime),
        project_code => $self->endpoint_config->{project_code},
        project_name => $self->endpoint_config->{project_name},
        issue => $issue_text,
        location_name => "",
        caller => "",
        resolve_by => "",
        location => {
            type => 'Point',
            coordinates => [
                # Add zero to force numeric context
                $args->{long} + 0,
                $args->{lat} + 0,
            ],
        }
    };

    if (@attachments) {
        $issue->{attachments} = \@attachments;
    }

    my $service_request_id = $self->get_integration->create_issue($issue);

    return $self->new_request(
        service_request_id => $service_request_id,
    )
}

sub get_service_request_updates { }

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

1;

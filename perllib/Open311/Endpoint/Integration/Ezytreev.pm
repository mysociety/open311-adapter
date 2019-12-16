package Open311::Endpoint::Integration::Ezytreev;

use Moo;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON::MaybeXS;
use Path::Tiny;
use YAML::XS qw(LoadFile);
use Digest::MD5 qw(md5_hex);
use DateTime::Format::W3CDTF;

use Integrations::Ezytreev;
use Open311::Endpoint::Service::UKCouncil::Ezytreev;

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

has integration_class => (
    is => 'ro',
    default => 'Integrations::Ezytreev'
);

has ezytreev => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(config_filename => $_[0]->jurisdiction_id) }
);

has category_mapping => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{category_mapping} }
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
    } keys %$services;
    return @services;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;
    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    my $url = $self->endpoint_config->{endpoint_url} . "UpdateEnquiry";

    my $body = {
        CRMXRef => "fms:" . $args->{attributes}->{fixmystreet_id},
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
    };
    my $request = POST $url,
        'Content-Type' => 'application/json',
        Accept => 'application/json',
        Content => encode_json($body);
    $request->authorization_basic(
        $self->endpoint_config->{username}, $self->endpoint_config->{password});

    my $response = $ua->request($request);
    if ($response->is_success) {
        $self->logger->debug($response->content);
        # Enquiry ID is the body of the response
        my $enquiry_id = $response->content;
        $enquiry_id =~ s/^\s+|\s+$//g;
        return $self->new_request(
            service_request_id => "ezytreev-" . $enquiry_id,
        );
    } else {
        die "Failed to send report to ezytreev";
    }
}

sub get_service_request_updates {
    my ($self, $args) = @_;
    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    my $url = $self->endpoint_config->{endpoint_url} . "GetEnquiryChanges";
    my $request = GET $url, Accept => 'application/json';
    $request->authorization_basic(
        $self->endpoint_config->{username}, $self->endpoint_config->{password});

    my $response = $ua->request($request);
    if ($response->is_success) {
        $self->logger->debug($response->content);
        my @updates;
        my $enquiry_changes = decode_json($response->content);
        my $w3c = DateTime::Format::W3CDTF->new;
        foreach my $enquiry (@$enquiry_changes) {
            # Ignore updates on enquiries that weren't created by FMS
            next unless substr($enquiry->{CRMXRef}, 0, 4) eq 'fms:';
            my $status = $self->reverse_status_mapping->{$enquiry->{EnquiryStatusCode}};
            if (!$status) {
                warn "Missing reverse status mapping for EnquiryStatus Code $enquiry->{EnquiryStatusCode} (EnquiryNumber $enquiry->{EnqRef})\n";
                $status = "open";
            }
            my $enquiry_id = $enquiry->{EnqRef};
            my $digest = md5_hex($enquiry->{EnquiryStatusCode} . '_' . $enquiry->{StatusDate});
            my $enquiry_date = substr($enquiry->{StatusDate}, 0, 10);
            my $dt = $w3c->parse_datetime($enquiry_date . "T" . $enquiry->{StatusTime} . "Z");
            my $status_description = $enquiry->{EnquiryStatusDescription};
            $status_description =~ s/^\s+|\s+$//g;
            my %update_args = (
                status => $status,
                update_id => $digest,
                service_request_id => "ezytreev-" . $enquiry->{EnqRef},
                description => $status_description,
                updated_datetime => $dt,
            );

            push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new(%update_args);
        }
        return @updates;
    } else {
        die "Failed to get report updates from ezytreev";
    }
}

sub get_service_request {
    my ($self, $service_request_id, $args) = @_;
    die "abstract method get_service_request not implemented";
}

__PACKAGE__->run_if_script;

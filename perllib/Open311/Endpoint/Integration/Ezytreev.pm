package Open311::Endpoint::Integration::Ezytreev;

use Moo;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON::MaybeXS;
use Path::Tiny;
use YAML::XS qw(LoadFile);

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

sub get_service_requests {
    my ($self, $args) = @_;
    die "abstract method get_service_requests not implemented";
}

sub get_service_request {
    my ($self, $service_request_id, $args) = @_;
    die "abstract method get_service_request not implemented";
}

__PACKAGE__->run_if_script;

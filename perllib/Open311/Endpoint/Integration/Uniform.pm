package Open311::Endpoint::Integration::Uniform;

use v5.14;
use warnings;

# use SOAP::Lite +trace => [qw(method debug)];

use DateTime::Format::W3CDTF;
use Digest::MD5 qw(md5_hex);
use Moo;
use Path::Tiny;
use JSON::MaybeXS;
use YAML::XS qw(LoadFile);

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::Logger';

use Integrations::Uniform;
use Open311::Endpoint::Service::UKCouncil;
use Open311::Endpoint::Service::Request::Update::mySociety;

has jurisdiction_id => ( is => 'ro' );

has endpoint_config => ( is => 'lazy' );

sub _build_endpoint_config {
    my $self = shift;
    my $config_file = path(__FILE__)->parent(5)->realpath->child('conf/council-' . $self->jurisdiction_id . '.yml');
    return {} if $ENV{TEST_MODE};
    my $conf = LoadFile($config_file);
    return $conf;
}

has service_whitelist => (
    is => 'ro',
    default => sub { $_[0]->endpoint_config->{service_whitelist} || {} },
);

has database => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{database} }
);

has username => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{username} }
);

has password => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{password} }
);

sub logon {
    my $self = shift;
    my $result = $self->get_integration->LogonToConnector({
        username => $self->username,
        password => $self->password,
        database => $self->database,
    })->result;

    $self->log_and_die($result->{Message}) unless $result->{LogonSuccessful} eq 'true';
}

sub services {
    my $self = shift;

    $self->logon;
    my $uniform_services = $self->get_integration->GetCnCodeList('SRRECTYPE')->result;
    $uniform_services = $uniform_services->{CodeList}{CnCode};

    my $services = $self->service_whitelist;
    my %uniform = map { $_->{CodeValue} => 1 } @$uniform_services;
    my @services = grep { $uniform{$_} || $uniform{$services->{$_}{parameters}{ServiceCode}} } sort keys %$services;

    @services = map {
        my $code = $_; # $_->{CodeValue};
        my $data = $services->{$code};
        my $name = $data->{name};
        my $service = $self->service_class->new(
            service_name => $name,
            service_code => $code,
            description => $name,
            $data->{group} ? (group => $data->{group}) : (),
            $data->{private} ? (keywords => ['private']) : (),
        );
        $service;
    } @services;
    return @services;
}

sub service_class {
    'Open311::Endpoint::Service::UKCouncil';
}

sub log_and_die {
    my ($self, $msg) = @_;
    $self->logger->error($msg);
    die "$msg\n";
}

sub process_service_request_args {
    my $self = shift;
    my $args = shift;

    my $services = $self->service_whitelist;
    my $data = $services->{$args->{service_code}};
    my $service_code = $args->{service_code};
    if ($data->{parameters}{ServiceCode}) {
        $service_code = $data->{parameters}{ServiceCode};
        $args->{attributes}{ADDLFTI} = $data->{name};
    }

    my $request = {
        service_code => $service_code,
        description => $args->{description},
        name => $args->{first_name} . " " . $args->{last_name},
        email => $args->{email},
        phone => $args->{phone},
    };

    # We need to bump some values up from the attributes hashref to
    # the $args passed
    foreach (qw/fixmystreet_id easting northing/) {
        if (defined $args->{attributes}->{$_}) {
            $request->{$_} = delete $args->{attributes}->{$_};
        }
    }

    if ($args->{media_url}->[0]) {
        foreach my $photo_url (@{ $args->{media_url} }) {
            $request->{description} .= "\n\n[ This report contains a photo, see: " . $photo_url . " ]";
        }
    }

    if ($args->{report_url}) {
        $request->{description} .= "\n\nView report on FixMyStreet: $args->{report_url}";
    }

    if ($args->{address_string}) {
        $request->{description} .= "\n\nLocation query entered: " . $args->{address_string};
    }

    return $request;
}

has integration_class => (
    is => 'ro',
    default => 'Integrations::Uniform'
);

sub get_integration {
    my $self = shift;
    my $integ = $self->integration_class;
    $integ = $integ->on_fault(sub { my($soap, $res) = @_; die ref $res ? $res->faultstring : $soap->transport->status, "\n"; })->want_som(1);
    $integ->config_filename($self->jurisdiction_id);
    return $integ;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    $self->log_and_die("No such service") unless $service;

    my @args = $self->process_service_request_args($args);
    $self->logger->debug(encode_json(\@args));

    $self->logon;
    my $web_service = $self->web_service($service);
    my $response = $self->get_integration->$web_service(@args);
    $self->log_and_die('Failed') unless $response;

    $response = $response->method;
    $self->log_and_die('Failed') unless $response;

    if ($response->{TransactionSuccess} && $response->{TransactionSuccess} eq 'False') {
        $self->log_and_die($response->{TransactionMessages}{TransactionMessage}{MessageBrief});
    }

    # Also SiteID
    my $id = $response->{ServiceRequestIdentification}{ReferenceValue};
    my $key = $response->{ServiceRequestIdentification}{ServiceRequestTechnicalKey} || '-';
    $self->log_and_die("Failed to find ID in success response: $key") unless $id;
    my $request = $self->new_request(
        service_request_id => $id,
    );

    return $request;
}

sub web_service {
    'SubmitGeneralServiceRequest';
}

sub get_service_request_updates {
    my ($self, $args) = @_;

    my $w3c = DateTime::Format::W3CDTF->new;
    my $start_time = $w3c->parse_datetime($args->{start_date});
    my $end_time = $w3c->parse_datetime($args->{end_date});

    $self->logon;
    my $result = $self->get_integration->GetChangedServiceRequestRefVals($args->{start_date});
    $result = $result->method;
    return unless $result;

    # given we don't have an update time set a default of 20 seconds in the
    # past or the end date. The -20 seconds is because FMS checks that comments
    # aren't in the future WRT when it made the request so the -20 gets round
    # that.
    my $update_time = DateTime->now->add( seconds => -20 );
    $update_time = $w3c->parse_datetime($args->{end_date}) if $args->{end_date};

    # Check for error
    my $requests = $result->{RefVals};
    $requests = [ $requests ] unless ref $requests eq 'ARRAY';
    my @updates;
    foreach (@$requests) {
        # RequestType is GENERAL
        my $request = $self->get_integration->GetGeneralServiceRequestByReferenceValue($_->{ReferenceValue});
        $request = $request->result;
        my $code = $request->{AdministrationDetails}->{StatusCode} || '';
        my $closing_code = $request->{AdministrationDetails}->{ClosingActionCode} || '';

        my $status = $self->map_status_code($code, $closing_code) || 'open';

        my $digest_key = join "-", $code, $closing_code;
        my $digest = substr(md5_hex($digest_key), 0, 8);
        my $update_id = $_->{ReferenceValue} . '_' . $digest;
        $update_id =~ s{/}{_}g;
        push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new(
            status => $status,
            update_id => $update_id,
            service_request_id => $_->{ReferenceValue},
            description => '',
            updated_datetime => $update_time,
        );
    }
    return @updates;
}

sub map_status_code {
    # Nothing by default
}

1;

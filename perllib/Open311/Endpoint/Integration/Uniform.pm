package Open311::Endpoint::Integration::Uniform;

use v5.14;
use warnings;

# use SOAP::Lite +trace => [qw(method debug)];

use DateTime::Format::W3CDTF;
use Digest::MD5 qw(md5_hex);
use Moo;
use Types::Standard ':all';
use JSON::MaybeXS;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::EndpointConfig';
with 'Role::Logger';

use Integrations::Uniform;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::UKCouncil::Uniform;
use Open311::Endpoint::Service::Request::Update::mySociety;

has jurisdiction_id => ( is => 'ro' );

has '+identifier_types' => (
    is => 'lazy',
    isa => HashRef[Any],
    default => sub {
        return {
            # some request IDs include slashes
            service_request_id => { type => '/open311/regex', pattern => qr/^ [\w_\-\/]+ $/ax },
        };
    },
);

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

    die $result->{Message} . "\n" unless $result->{LogonSuccessful} eq 'true';
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
        foreach (@{$data->{questions}}) {
            my %attribute = (
                code => $_->{code},
                description => $_->{description},
            );
            if ($_->{variable} // 1) {
                $attribute{required} = 1;
            } else {
                $attribute{variable} = 0;
                $attribute{required} = 0;
            }
            if ($_->{values}) {
                $attribute{datatype} = 'singlevaluelist';
                $attribute{values} = { map { $_ => $_ } @{$_->{values}} };
            } else {
                $attribute{datatype} = 'string';
            }
            push @{$service->attributes}, Open311::Endpoint::Service::Attribute->new(%attribute);
        }
        $service;
    } @services;
    return @services;
}

sub service_class {
    'Open311::Endpoint::Service::UKCouncil::Uniform';
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

    if ($data->{allocated}) {
        $request->{allocated} = $data->{allocated};
    }

    # We need to bump some values up from the attributes hashref to
    # the $args passed
    foreach (qw/fixmystreet_id easting northing uprn/) {
        if (defined $args->{attributes}->{$_}) {
            $request->{$_} = delete $args->{attributes}->{$_};
        }
    }
    delete $args->{attributes}->{NSGName};
    $request->{xtra} = $args->{attributes};

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
    $self->log_identifier($self->jurisdiction_id);
    return $integ;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service\n" unless $service;

    my @args = $self->process_service_request_args($args);
    $self->logger->debug(encode_json(\@args));

    $self->logon;
    my $web_service = $self->web_service($service);
    my $response = $self->get_integration->$web_service(@args);
    die "Failed" unless $response;

    $response = $response->method;
    die "Failed" unless $response;

    if ($response->{TransactionSuccess} && $response->{TransactionSuccess} eq 'False') {
        die $response->{TransactionMessages}{TransactionMessage}{MessageBrief} . "\n";
    }

    # Also SiteID
    my $id = $response->{ServiceRequestIdentification}{ReferenceValue};
    my $key = $response->{ServiceRequestIdentification}{ServiceRequestTechnicalKey} || '-';
    die "Failed to find ID in success response: $key\n" unless $id;
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
    my $result = eval { $self->get_integration->GetChangedServiceRequestRefVals($args->{start_date}) };
    return unless $result;
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
        next unless $_->{RequestType} eq 'GENERAL';
        my $request = eval { $self->_get_request($_->{ReferenceValue}) };
        next unless $request;
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

sub _get_request {
    my ($self, $id) = @_;
    my $request = $self->get_integration->GetGeneralServiceRequestByReferenceValue($id);
    $request = $request->result;
    return $request if ref $request;
    $self->logger->error('No such request');
}

sub _get_visits {
    my ($self, $request) = @_;
    my $visits = $request->{InspectionDetails}->{Visits} || { Visit => [] };
    $visits = $visits->{Visit};
    $visits = [ $visits ] unless ref $visits eq 'ARRAY';
    return $visits;
}

sub post_service_request_update {
    my ($self, $args) = @_;

    $self->logon;

    if ($args->{media_url}->[0]) {
        $args->{description} .= "\n\n[ This update contains a photo, see: " . $args->{media_url}->[0] . " ]";
    }

    # Loses any timezone on submission, so make sure it's in UK local time.
    my $w3c = DateTime::Format::W3CDTF->new;
    my $time = $w3c->parse_datetime($args->{updated_datetime});
    $time->set_time_zone('Europe/London');
    $time->set_time_zone('floating');
    $args->{updated_datetime} = $w3c->format_datetime($time);

    my $request = $self->_get_request($args->{service_request_id});
    my $inspection_id = $request->{InspectionDetails}->{ReferenceValue};
    $self->get_integration->AddVisitsToInspection($inspection_id, $args); # Doesn't return anything

    # Get the request again, to get the ID of the newly added visit...
    $request = $self->_get_request($args->{service_request_id});
    my $visits = $self->_get_visits($request);
    my $num_visits = @$visits;

    # The visits are not always in the order added...
    my $visit_id;
    (my $desc = $args->{description}) =~ s/\s+/ /g;
    foreach (@$visits) {
        $_->{Comments} =~ s/\s+/ /g;
        if ($_->{OfficerCode} eq 'EHCALL' && $_->{VisitTypeCode} eq 'EHCUR' && $_->{Comments} eq $desc && $_->{ScheduledDateOfVisit} eq $args->{updated_datetime}) {
            $visit_id = $_->{ReferenceValue};
            last;
        }
    }
    die "Could not find matching Visit\n" unless $visit_id;

    $self->get_integration->AddActionsToVisit($visit_id, $args); # Doesn't return anything

    my $update_id = $args->{service_request_id};
    $update_id =~ s{/}{_}g;
    $update_id .= "_" . $num_visits;

    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => lc $args->{status},
        update_id => $update_id,
    );
}

1;

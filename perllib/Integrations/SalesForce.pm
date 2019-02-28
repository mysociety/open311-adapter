package Integrations::SalesForce;

use Moo;
use HTTP::Request;
use LWP::UserAgent;

with 'Role::Logger';

use JSON::MaybeXS;

has 'endpoint_url' => (
    is => 'ro',
    default => sub { die "abstract method endpoint_url not overridden" }
);

has 'credentials' => (
    is => 'ro',
    default => sub { die "abstract method credentials not overridden" }
);

has 'requests_endpoint' => (
    is => 'ro',
    default => sub { shift->endpoint_url . 'FixMyStreet'; }
);

has 'services_endpoint' => (
    is => 'ro',
    default => sub { shift->endpoint_url . 'FixMyStreetInfo' }
);

has 'updates_endpoint' => (
    is => 'ro',
    default => sub { shift->endpoint_url . 'FixMyStreetUpdates' }
);

has 'get_headers' => (
    is => 'ro',
    default => sub {
        my $h = HTTP::Headers->new;
        $h->header('Content-Type' => 'application/json');
        $h->header('Authorization' => 'Bearer ' . shift->credentials );

        return $h;
    }
);

sub get {
    my ($self, $url) = @_;

    my $req = HTTP::Request->new(GET => $url, $self->get_headers);

    return $self->_send_request($req);
}

sub post {
    my ($self, $url, $data) = @_;

    my $req = HTTP::Request->new(POST => $url, $self->get_headers);
    $req->content($data);

    return $self->_send_request($req);
}

# this method here so we can mock the request/response bit
# out for testing
sub _get_response {
    my ($self, $req) = @_;
    my $ua = LWP::UserAgent->new();
    return $ua->request($req);
}

sub _send_request {
    my ($self, $req) = @_;

    $self->logger->debug($req->url->as_string);
    $self->logger->debug($req->content);

    my $response = $self->_get_response($req);

    $self->logger->debug($response->content);

    my $content = decode_json($response->content);

    unless ($response->code == 200) {
        my $message = $response->message;
        my $code = $response->code;
        if (ref $content eq 'ARRAY' and $content->[0]->{errorCode}) {
            $message = $content->[0]->{message};
            $code = $content->[0]->{errorCode};
        }

        die sprintf(
            "Error fetching from SalesForce: %s (%d)\n",
            $message,
            $code
        );
    }

    return $content;
}

sub get_requests {
    my $self = shift;

    return $self->get($self->requests_endpoint . '?all');
}

sub get_request {
    my ($self, $id) = @_;

    return $self->get($self->requests_endpoint . '?id=' . $id);
}

sub post_request {
    my ($self, $service, $args) = @_;

    my $name = join(' ', ($args->{first_name}, $args->{last_name}));

    my $formatter = DateTime::Format::Strptime->new(pattern => '%FT%T%z');
    my $date = $formatter->format_datetime(DateTime->now());

    my $values = {
            agency_responsible__c => 'Rutland County Council',
            description__c => $args->{attributes}->{description},
            detail__c => $args->{attributes}->{description},
            interface_used__c => 'Web interface',
            lat__c => $args->{lat} + 0,
            long__c => $args->{long} + 0,
            agency_sent_datetime__c => $date,
            requested_datetime__c => $date,
            updated_datetime__c => $date,
            requestor_name__c => $name,
            contact_name__c => $name,
            status__c => 'open',
            Service_Area__c => $args->{service_code},
            title__c => $args->{attributes}->{title},
            service_request_id__c => $args->{attributes}->{external_id} + 0,
    };

    # add category specific attributes
    for my $extra (keys %{ $args->{attributes} } ) {
        unless (exists $service->internal_attributes->{$extra}) {
            $values->{$extra} = $args->{attributes}->{$extra};
        }
    }

    $values->{contact_phone__c} = $args->{phone} if $args->{phone};
    $values->{contact_email__c} = $args->{email} if $args->{email};

    if ($args->{media_url}->[0]) {
        $values->{photos} = $args->{media_url};
    }

    my $data = [ $values ];

    my $json = encode_json($data);

    my $response = $self->post($self->requests_endpoint, encode_json($data));

    return $response->[0]->{Id};
}

sub post_update {
    my ($self, $args) = @_;

    my $data = [ {
        status__c => $args->{status},
        id => $args->{service_request_id},
        #update_comments_id__c => $args->{description},
        update_comments__c => $args->{description},
    } ];

    my $json = encode_json($data);
    my $response = $self->post($self->requests_endpoint, encode_json($data));

    return $response->[0]->{Id} || undef;
}

sub get_updates {
    my $self = shift;
    return $self->get($self->updates_endpoint . '?updates');
}

sub get_services {
    my ($self, $args) = @_;

    my $services = $self->get($self->services_endpoint . '?summary');

    my @services;

    for my $service (@{ $services->{CategoryInformation} }) {
        push @services, $service;
    }

    return @services;
}

sub get_service {
    my ($self, $id, $args) = @_;

    my $service = $self->get($self->services_endpoint . '?id=' . $id);

    return $service;
}

1;

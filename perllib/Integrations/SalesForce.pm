package Integrations::SalesForce;

use Moo;
use HTTP::Request;
use LWP::UserAgent;

use JSON::MaybeXS;

has 'endpoint_url' => (
    is => 'ro',
    default => sub { die "abstract method endpoint_url not overridden" }
);

has 'credentials' => (
    is => 'ro',
    default => sub { die "abstract method credentials not overridden" }
);

has 'services_endpoint' => (
    is => 'ro',
    default => sub { shift->endpoint_url . 'FixMyStreetInfo' }
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

# this method here so we can mock the request/response bit
# out for testing
sub _get_response {
    my ($self, $req) = @_;
    my $ua = LWP::UserAgent->new();
    return $ua->request($req);
}

sub _send_request {
    my ($self, $req) = @_;

    my $response = $self->_get_response($req);
    my $content = decode_json($response->content);

    unless ($response->code == 200) {
        my $message = $response->message;
        if (ref $content eq 'ARRAY' and $content->[0]->{errorCode}) {
            $message = $content->[0]->{message};
        }

        die sprintf(
            'Error fetching from SalesForce: %s (%d)',
            $message,
            $response->code
        );
    }

    return $content;
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

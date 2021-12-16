package Integrations::SalesForce::Base;

# Shared code by existing SalesForce integrations

use Moo;
use HTTP::Request;
use HTTP::Request::Common;
use LWP::UserAgent;

with 'Role::Config';
with 'Role::Logger';
with 'Role::Memcached';

use JSON::MaybeXS;
use Path::Tiny;
use Crypt::JWT qw(encode_jwt);

has 'endpoint_url' => (
    is => 'ro',
    default => sub { $_[0]->config->{endpoint} || '' }
);

has 'credentials' => (
    is => 'lazy',
    default => sub {
        my $self = shift;

        if ($self->config->{credentials}) {
            return $self->config->{credentials};
        }

        if (my $key = $self->config->{private_key}) {
            my $key_content = path(__FILE__)->parent(5)->realpath->child('keys')->child($key)->slurp;

            my $data = {
                iss => $self->config->{client_id},
                aud => $self->config->{login_url},
                sub => $self->config->{username},
            };

            my $token = encode_jwt(payload => $data, relative_exp => 300, alg => 'RS256', key => \$key_content);

            my $req = HTTP::Request::Common::POST($self->config->{auth_url}, [
                    grant_type => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                    assertion => $token
                ] );
            my $ua = LWP::UserAgent->new();
            my $res = $ua->request($req);
            my $content = decode_json($res->content);
            return $content->{access_token};
        }

        return {};
    }
);


has 'get_headers' => (
    is => 'lazy',
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

    unless ($response->code == 200 || $response->code == 201) {
        my $message = $response->message;
        my $code = $response->code;
        if (ref $content eq 'ARRAY' and $content->[0]->{errorCode}) {
            $message = $content->[0]->{message};
            $code = $content->[0]->{errorCode};
        }

        die sprintf(
            "Error fetching from SalesForce: %s (%s)\n",
            $message,
            $code
        );
    }

    return $content;
}

1;

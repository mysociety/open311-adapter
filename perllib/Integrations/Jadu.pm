package Integrations::Jadu;

use v5.14;
use warnings;

use Data::Dumper;
use HTTP::Request;
use HTTP::Request::Common;
use JSON::MaybeXS qw(decode_json encode_json);
use LWP::UserAgent;
use Moo;

with 'Role::Config';
with 'Role::Logger';
with 'Role::Memcached';

has base_url => (
    is => 'lazy',
    default => sub { $_[0]->config->{api_base_url}  }
);

has api_key => (
    is => 'lazy',
    default => sub { $_[0]->config->{api_key}  }
);

has username => (
    is => 'lazy',
    default => sub { $_[0]->config->{username}  }
);

has password => (
    is => 'lazy',
    default => sub { $_[0]->config->{password}  }
);

has ua => (
    is => 'lazy',
    default => sub { LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter") }
);

has api_token => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my $token = $self->memcache->get('api_token');
        unless ($token) {
            $token = $self->sign_in_and_get_token;
            $self->memcache->set('api_token', $token, time() + $self->api_token_expiry_seconds);
        }
        return $token;
    },
);

has api_token_expiry_seconds => (
    is => 'ro',
    default => sub { 60 * 30 },
);

has api_key_header_name => (
    is => 'ro',
    default => 'X-API-KEY',
);

has api_token_header_name => (
    is => 'ro',
    default => 'X-API-TOKEN',
);


sub _fail {
    my ($self, $request, $response, $message) = @_;
    my $log = sprintf(
        "%s
        Sent: %s
        Got: %s",
        $message, Dumper($request), Dumper($response)
    );
    $self->logger->error($log);
    die $message;
}

sub sign_in_and_get_token {
    my $self = shift;
    my $request = HTTP::Request->new(
        'POST',
        $self->base_url . "sign-in",
        [
            $self->api_key_header_name => $self->api_key,
            "Content-Type" => "application/json",
        ],
        encode_json({
            username => $self->username,
            password => $self->password,
        })
    );
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail($request, $response, "sign-in failed");
    }
    my $response_json = decode_json($response->content);
    if (!$response_json->{token}) {
        $self->_fail($request, $response, "token not found in sign-in response");
    }
    return $response_json->{token};
}

sub create_case_and_get_reference {
    my ($self, $case_type, $payload) = @_;
    my $url = $self->base_url . $case_type . "/case/create";
    my $request = HTTP::Request::Common::POST(
        $url,
        $self->api_key_header_name => $self->api_key,
        $self->api_token_header_name => $self->api_token,
        "Content-Type" => "application/json",
        Content => encode_json($payload)
    );

    $self->logger->debug($url . " sending:\n" . Dumper($payload));
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail($request, $response, "create case failed");
    }
    my $response_json = decode_json($response->content);
    if (!$response_json->{reference}) {
        $self->_fail($request, $response, "case reference not found in create case response");
    }
    $self->logger->debug($url . " got:\n" . Dumper($response_json));
    return $response_json->{reference};
}

sub attach_file_to_case {
    my ($self, $case_type, $case_reference, $filepath, $filename) = @_;
    my $url = $self->base_url . "case/" . $case_reference . "/attach";
    my $content = [
        json => encode_json({name => $filename}),
        file => [$filepath]
    ];
    my $request = HTTP::Request::Common::POST(
        $url,
        $self->api_key_header_name => $self->api_key,
        $self->api_token_header_name => $self->api_token,
        "Content-Type" => "form-data",
        Content => $content
    );
    $self->logger->debug($url . " sending:\n" . Dumper($content));
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail($request, $response, "failed to attach file to case");
    }
    $self->logger->debug($url . " got:\n" . Dumper(decode_json($response->content)));
}

sub get_case_summaries_by_filter {
    my ($self, $case_type, $filter_name, $page_number) = @_;
    my $url = $self->base_url . "filters/" . $filter_name . "/summaries?page=" . $page_number;
    my $request = HTTP::Request::Common::GET(
        $url,
        $self->api_key_header_name => $self->api_key,
        $self->api_token_header_name => $self->api_token,
    );
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail($request, $response, "failed to get case summaries by filter");
    }
    my $response_json = decode_json($response->content);
    $self->logger->debug($url . " got: " . Dumper($response_json));
    return $response_json;
}

1;

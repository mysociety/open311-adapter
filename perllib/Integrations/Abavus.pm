package Integrations::Abavus;

use DateTime::Format::W3CDTF;
use Moo;
use LWP::UserAgent;
use HTTP::Headers;
use HTTP::Request;
use HTTP::Request::Common;
use URI;
use Try::Tiny;
use Encode qw(encode_utf8);
use JSON::MaybeXS qw(encode_json decode_json);
use List::Util qw[min];
use POSIX qw(ceil);

with 'Role::Config';
with 'Role::Logger';
with 'Role::Memcached';

sub api_call {
    my ($self, %args) = @_;

    my $call = $args{call};
    my $body = $args{body};

    my $ua = LWP::UserAgent->new(
        agent => "FixMyStreet/open311-adapter",
        timeout => 5*60,
    );
    my $method = $args{method};
    $method = $body ? 'POST' : 'GET' unless $method;
    my $uri = URI->new( $self->config->{api_url} . $call );
    $uri->query_form(%{ $args{params} });
    my $request = HTTP::Request->new($method, $uri);
    $request->header(iPublicKey => $self->config->{api_key});
    if ($body) {
        $request->content_type('application/json; charset=UTF-8');
        $request->content(encode_json($body));
        $self->logger->debug($call);
        $self->logger->debug(encode_json($body));
    }
    my $response = $ua->request($request);
    if ($response->is_success) {
        $self->logger->debug($response->content) if $body;
        return decode_json($response->content);
    } else {
        $self->logger->error($call);
        $self->logger->error(encode_json($body)) if $body and (ref $body eq 'HASH' || ref $body eq 'ARRAY');
        $self->logger->error($response->content);
        try {
            my $json_response = decode_json($response->content);
            my $code = $json_response->{errorCode} || "";
            my $codeString = $json_response->{errorCodeString} || "";
            my $msg = $json_response->{debugErrorMessage} || "";
            die "Abavus API call failed: [$code $codeString] $msg";
        } catch {
            die $response->content;
        };
    }
}

1;

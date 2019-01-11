package Integrations::Alloy;

use DateTime::Format::W3CDTF;
use Moo;
use Cache::Memcached;
use LWP::UserAgent;
use HTTP::Headers;
use HTTP::Request;
use URI;
use Encode qw(encode_utf8);
use JSON::MaybeXS qw(encode_json decode_json);


sub api_url { $_[0]->config->{api_url} }

sub api_key { $_[0]->config->{api_key} }

has memcache_namespace  => (
    is => 'lazy',
    default => sub { $_[0]->config_filename }
);

has memcache => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        new Cache::Memcached {
            'servers' => [ '127.0.0.1:11211' ],
            'namespace' => 'open311adapter:' . $self->memcache_namespace . ':',
            'debug' => 0,
            'compress_threshold' => 10_000,
        };
    },
);

sub api_call {
    my ($self, $call, $params, $body) = @_;

    my $ua = LWP::UserAgent->new(
        agent => "FixMyStreet/open311-adapter",
        default_headers => HTTP::Headers->new(
            apiKey => $self->api_key
        )
    );
    my $method = $body ? 'POST' : 'GET';
    my $uri = URI->new( $self->api_url . $call );
    $uri->query_form(%$params);
    my $request = HTTP::Request->new($method, $uri);
    if ($body) {
        $request->content_type('application/json; charset=UTF-8');
        $request->content(encode_utf8(encode_json($body)));
    }
    my $response = $ua->request($request);
    if ($response->is_success) {
        return decode_json($response->content);
    } else {
        printf STDERR "failed!", $response->content;
    }
}

sub get_source_types {
    my $self = shift;

    return $self->api_call("source-type", { propertyName => $self->config->{source_type_property_name} })->{sourceTypes};
}

1;
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
            apiKey => $self->config->{api_key}
        )
    );
    my $method = $body ? 'POST' : 'GET';
    my $uri = URI->new( $self->config->{api_url} . $call );
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

sub get_source_for_source_type_id {
    my $self = shift;
    my $source_type_id = shift;

    my $sources = $self->api_call("source", { sourceTypeId => $source_type_id })->{sources};
    # TODO: Check that the source is valid - e.g. startDate/endDate/softDeleted fields
    # TODO: What if there's zero or more than one source?
    return @$sources[0] if @$sources;
}

sub get_parent_attribute_id {
    my $self = shift;

    return 0;
}

sub get_sources {
    my $self = shift;

    my $key = "get_sources";
    my $expiry = 1800; # cache all these API calls for 30 minutes
    my $sources = $self->memcache->get($key);
    unless ($sources) {
        $sources = [];
        my $source_types = $self->get_source_types();
        for my $source_type (@$source_types) {
            my $alloy_source = $self->get_source_for_source_type_id($source_type->{sourceTypeId});

            my $source = {
                source_type_id => $source_type->{sourceTypeId},
                description => $source_type->{description},
                source_id => $alloy_source->{sourceId},
                parent_attribute_id => $self->get_parent_attribute_id($source_type->{sourceTypeId}),
            };

            my @attributes = ();
            my $source_type_attributes = $source_type->{attributes};
            for my $source_attribute (@$source_type_attributes) {
                push @attributes, {
                    description => $source_attribute->{description},
                    id => $source_attribute->{attributeId},
                    required => $source_attribute->{required},
                    datatype => "string", # XXX fix this
                };
            }
            $source->{attributes} = \@attributes;

            push @{$sources}, $source;
        }
        $self->memcache->set($key, $sources, $expiry);
    }
    return $sources;
}

1;
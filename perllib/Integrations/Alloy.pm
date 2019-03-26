package Integrations::Alloy;

use DateTime::Format::W3CDTF;
use Moo;
use Cache::Memcached;
use LWP::UserAgent;
use HTTP::Headers;
use HTTP::Request;
use HTTP::Request::Common;
use URI;
use Try::Tiny;
use Encode qw(encode_utf8);
use JSON::MaybeXS qw(encode_json decode_json);

with 'Role::Logger';


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
    my ($self, $call, $params, $body, $is_file) = @_;

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
    if ($is_file) {
        $request = HTTP::Request::Common::POST(
            $uri,
            Content_Type => 'form-data',
            Content => [ file => [undef, $params->{'model.name'}, Content => $body] ]
        );
    } elsif ($body) {
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
            die "Alloy API call failed: [$json_response->{errorCode} $json_response->{errorCodeString}] $json_response->{debugErrorMessage}";
        } catch {
            die $response->content;
        };
    }
}

sub get_source_types {
    my $self = shift;

    my %whitelist = map { $_ => 1} @{ $self->config->{source_type_id_whitelist} };
    my $source_types = $self->api_call("source-type", { propertyName => $self->config->{source_type_property_name} })->{sourceTypes};
    return grep { $whitelist{$_->{sourceTypeId}} } @$source_types;
}

sub get_source_for_source_type_id {
    my $self = shift;
    my $source_type_id = shift;

    my $sources = $self->api_call("source", { sourceTypeId => $source_type_id })->{sources};
    # TODO: Check that the source is valid - e.g. startDate/endDate/softDeleted fields
    # TODO: What if there's zero or more than one source?
    return @$sources[0] if @$sources;
}

sub get_valuetype_mapping {
    my $self = shift;

    my $mapping = {
        BOOLEAN => "number", # 0/1?
        STRING => "text", # or maybe string?
        OPTION => "singlevaluelist",
        DATETIME => "datetime",
        DATE => "datetime", # this and TIME are obviously not perfect
        TIME => "datetime",
        INTEGER => "number",
        FLOAT => "number",
        GEOMETRY => "string", # err. Probably GeoJSON?
        IRG_REF => "string", # err. This is an item lookup
    };
    my $valuetypes = $self->api_call("reference/value-type");
    my %mapping = map { $_->{valueTypeId} => $mapping->{$_->{code}} } @$valuetypes;
    return \%mapping;
}

sub get_parent_attributes {
    my $self = shift;
    my $source_type_id = shift;

    # TODO: What's the correct behaviour if there's none?
    return $self->api_call("source-type/$source_type_id/linked-source-types", { irgConfigCode => $self->config->{irg_config_code} });
}

sub get_sources {
    my $self = shift;

    my $key = "get_sources";
    my $expiry = 1800; # cache all these API calls for 30 minutes
    my $sources = $self->memcache->get($key);
    unless ($sources) {
        $sources = [];
        my $type_mapping = $self->get_valuetype_mapping();
        my @source_types = $self->get_source_types();
        for my $source_type (@source_types) {
            my $alloy_source = $self->get_source_for_source_type_id($source_type->{sourceTypeId});

            my $source = {
                source_type_id => $source_type->{sourceTypeId},
                description => $source_type->{description},
                source_id => $alloy_source->{sourceId},
            };

            my @attributes = ();
            my $source_type_attributes = $source_type->{attributes};
            for my $source_attribute (@$source_type_attributes) {
                next unless $source_attribute->{isRequired};

                my $datatype = $type_mapping->{$source_attribute->{valueTypeId}} || "string";
                my %values = ();
                if ($datatype eq 'singlevaluelist' && $source_attribute->{attributeOptionTypeId}) {
                    # Fetch all the options for this attribute from the API
                    my $options = $self->api_call("attribute-option-type/$source_attribute->{attributeOptionTypeId}")->{optionList};
                    for my $option (@$options) {
                        $values{$option->{optionId}} = $option->{optionDescription};
                    }
                }

                push @attributes, {
                    description => $source_attribute->{description},
                    name => $source_attribute->{name},
                    id => $source_attribute->{attributeId},
                    required => $source_attribute->{isRequired},
                    datatype => $datatype,
                    values => \%values,
                };
            }
            $source->{attributes} = \@attributes;
            push @$sources, $source;
        }
        $self->memcache->set($key, $sources, $expiry);
    }
    return $sources;
}

1;
package Integrations::AlloyV2;

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


sub detect_type {
    my ($self, $photo) = @_;
    return 'image/jpeg' if $photo =~ /^\x{ff}\x{d8}/;
    return 'image/png' if $photo =~ /^\x{89}\x{50}/;
    return 'image/tiff' if $photo =~ /^II/;
    return 'image/gif' if $photo =~ /^GIF/;
    return '';
}

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
    $request->header(Authorization => 'Bearer ' . $self->config->{api_key});
    if ($args{is_file}) {
        $request = HTTP::Request::Common::POST(
            $uri,
            Content_Type => $self->detect_type($body),
            'content-disposition' => "attachment; filename=\"$args{filename}\"",
            Content => $body
        );
        $request->header(Authorization => 'Bearer ' . $self->config->{api_key});
    } elsif ($body) {
        $request->content_type('application/json; charset=UTF-8');
        $request->content(encode_json($body));
        $self->logger->debug($call);
        $self->logger->debug(encode_json($body));
    } else {
        $self->logger->debug($call);
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
            die "Alloy API call failed: [$code $codeString] $msg";
        } catch {
            die $response->content;
        };
    }
}

sub get_designs {
    my $self = shift;

    my $design = $self->api_call(
        call => "design/" . $self->config->{rfs_design},
    );
    return ($design);
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
    return $mapping;
    my $valuetypes = $self->api_call(call => "reference/value-type");
    my %mapping = map { $_->{valueTypeId} => $mapping->{$_->{code}} } @$valuetypes;
    return \%mapping;
}

sub get_parent_attributes {
    my $self = shift;
    my $design_code = shift;

    # TODO: What's the correct behaviour if there's none?
    my $design = $self->api_call(
        call => "design/$design_code",
    );

    for my $att ( @{ $design->{design}->{attributes} } ) {
        $self->logger->debug($att->{name});
        if ( $att->{name} eq $self->config->{parent_attribute_name} ) {
            return $att->{code};
        }
    }
}

sub update_attributes {
    my ($self, $values, $map, $attributes) = @_;

    for my $key ( keys %$map ) {
        push @$attributes, {
            attributeCode => $map->{$key},
            value => $values->{$key}
        }
    }

    return $attributes;
}

sub attributes_to_hash {
    my ($self, $item) = @_;

    my $attributes = {};
    for my $att ( @{ $item->{attributes} } ) {
        $attributes->{$att->{attributeCode}} = $att->{value};
    }

    return $attributes;
}

sub design_attributes_to_hash {
    my ($self, $item) = @_;

    my $attributes = {};
    for my $att ( @{ $item->{design}->{attributes} } ) {
        $attributes->{$att->{name}} = {
            code => $att->{code},
            linked_code => $att->{options}->{code}
        }
    }

    return $attributes;
}


sub search {
    my ($self, $body_base, $skip_count) = @_;

    my $stats = { result => 1 };
    unless ($skip_count) {
        my $stats_body = { %$body_base };
        $stats_body->{type} = 'MathAggregation';
        $stats_body->{properties}->{aggregationType} = 'Count';

        $stats = $self->api_call(
            call => "aqs/statistics",
            body => { aqs => $stats_body },
        );
    }

    my $result_count = $stats->{results}[0]{value}{value} + 0;
    return [] unless $result_count;

    my $maxPages = 100;
    my $pageSize = $result_count <= 10000 ? 100 : ( ceil($result_count / $maxPages) + 1 );
    my $pages = int( $result_count / $pageSize ) + 1;

    my $query_body = $body_base;
    $query_body->{type} = 'Query';

    my @results;
    my $page = 1;
    while ($page <= $pages) {
        my $result = $self->api_call(
            call => "aqs/query",
            params => { page => $page, pageSize => $pageSize },
            body => { aqs => $query_body },
        );

        $page++;

        next unless $result->{results};
        push @results, @{ $result->{results} }
    }

    return \@results;
}

1;

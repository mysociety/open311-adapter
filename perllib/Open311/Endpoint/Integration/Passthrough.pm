=head1 NAME

Open311::Endpoint::Integration::Passthrough - a transparent proxy integration

=head1 SUMMARY

This integration passes the data on that it receives directly. This is to allow
a third party Open311 server to sit alongside open311-adapter integrations
within a Multi service. Validation will be performed on the data coming back.

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::Passthrough;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';
with 'Role::Logger';
with 'Role::Memcached';

use DateTime::Format::W3CDTF;
use LWP::UserAgent;
use URI;
use XML::Simple qw(:strict);
use Open311::Endpoint::Service;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request;
use Open311::Endpoint::Service::Request::ExtendedStatus;
use Open311::Endpoint::Service::Request::Update::mySociety;

=head2 configuration

To use this integration, subclass it and provide a C<jurisdiction_id> in the
subclass's C<BUILDARGS>. This will then be used to look up a configuration file
which should contain an C<endpoint> and an C<api_key>.

=cut

has jurisdiction_id => ( is => 'ro' );
has endpoint => ( is => 'ro' );
has api_key => ( is => 'ro' );

has batch_service => ( is => 'ro' );

=head2 ignore_services

Provide a list of service codes that should be ignored and not passed back from
the proxied backend.

=cut

has ignore_services => ( is => 'ro', => default => sub { [] } );

has updates_url => ( is => 'ro', default => 'servicerequestupdates.xml' );

sub service_request_content {
    '/open311/service_request_extended'
}

# This isn't called xml because the root Endpoint class has that attribute
has pt_xml => (
    is => 'lazy',
    default => sub {
        my $group_tags = {
            services => 'service',
            attributes => 'attribute',
            values => 'value',
            service_requests => 'request',
            errors => 'error',
            service_request_updates => 'request_update',
            groups => 'group',
        };
        XML::Simple->new(
            SuppressEmpty => 1,
            KeyAttr => [],
            ForceArray => [ values %$group_tags ],
            GroupTags => $group_tags,
        );
    },
);

has ua => (
    is => 'lazy',
    default => sub {
        LWP::UserAgent->new();
    },
);

has date_parser => (
    is => 'lazy',
    default => sub { DateTime::Format::W3CDTF->new },
);

=head2 _request

Requests are made to the endpoint, and returned data parsed as XML. POST
requests include the api_key. An error in the returned data will cause
the function to die.

=cut

sub _request {
    my ($self, $method, $url, $params) = @_;
    $url = URI->new($self->endpoint . $url);

    my $auth = delete $params->{Authorization};
    my %headers;
    $headers{Authorization} = $auth if $auth;

    my $resp;
    if ($method eq 'POST') {
        $params->{api_key} = $self->api_key;
        $self->logger->debug($url);
        $self->logger->dump($params);
        $resp = $self->ua->post($url, $params, %headers);
    } else {
        $url->query_form(%$params);
        $self->logger->debug($url);
        $resp = $self->ua->get($url, %headers);
    }
    my $content = $resp->decoded_content( charset => $url =~ /bathnes/ ? 'utf-8' : undef );
    $self->logger->debug($content);
    my $xml = $self->pt_xml->XMLin(\$content);
    die $xml->{error}[0]->{description} . "\n" if $xml->{error};
    return $xml;
}

=head2 services

Transparently passed through to the backend to fetch a list of services.

=cut

sub services {
    my ($self, $args) = @_;
    my $xml = $self->_request(GET => 'services.xml');
    my @services;
    my %ignore = map { $_ => 1 } @{$self->ignore_services};
    foreach (@{$xml->{service}}) {
        next if $ignore{$_->{service_code}};
        next unless $_->{service_name};
        $_->{groups} = delete $_->{group} if $_->{group};
        $_->{description} ||= '';
        $_->{keywords} = [ split /\s*,\s*/, $_->{keywords} ] if $_->{keywords};
        my $service = Open311::Endpoint::Service->new(%$_);
        if ($_->{metadata} eq 'true') {
            # An empty one is enough to get the metadata true passed out
            my $attribute = Open311::Endpoint::Service::Attribute->new;
            push @{$service->attributes}, $attribute;
        }
        push @services, $service;
    }
    return @services;
}

=head2 service

Transparently passed through to the backend to fetch a service.

=cut

sub service {
    my ($self, $service_id, $args) = @_;
    my $data = $self->memcache->get("service/$service_id");
    return $data if $data;
    my $xml = $self->_request(GET => "services/$service_id.xml");
    my $service = Open311::Endpoint::Service->new(
        service_code => $service_id,
        type => $self->batch_service ? 'batch' : 'realtime',
    );
    foreach (@{$xml->{attributes}}) {
        $_->{required} = $_->{required} eq 'true' ? 1 : 0;
        $_->{variable} = $_->{variable} eq 'true' ? 1 : 0;
        # Need to maintain the order
        $_->{values_sorted} = [ map { $_->{key} } @{$_->{values}} ];
        $_->{values} = { map { $_->{key} => $_->{name} } @{$_->{values}} };
        $_->{datatype} ||= 'string';
        $_->{description} ||= '';
        my $attribute = Open311::Endpoint::Service::Attribute->new(%$_);
        push @{ $service->attributes }, $attribute;
    }
    $self->memcache->set("service/$service_id", $service, time() + 60);
    return $service;
}

=head2 post_service_request

Resets the attributes to be in the format they were received, then passes
through to the backend to post a service request.

=cut

sub post_service_request {
    my ($self, $service, $args) = @_;

    _strip_args($args);
    my $xml = $self->_request(POST => "requests.xml", $args);
    if (my $token = $xml->{request}[0]{token}) {
        my $result = Open311::Endpoint::Service::Request->new(token => $token);
        return $result;
    }
    my $id = $xml->{request}[0]{service_request_id};
    my $result = Open311::Endpoint::Service::Request->new(service_request_id => $id);
    return $result;
}

sub get_token {
    my ($self, $token, $args) = @_;

    my $xml = $self->_request(GET => "tokens/$token.xml");
    my $result = Open311::Endpoint::Service::Request->new(%{$xml->{request}[0]});
    return $result;
}

=head2 post_service_request_update

Resets the attributes to be in the format they were received, then passes
through to the backend to post a service request update.

=cut

sub post_service_request_update {
    my ($self, $args) = @_;

    _strip_args($args);
    my $xml = $self->_request(POST => $self->updates_url, $args);
    my $id = $xml->{request_update}[0]{update_id};
    my $result = Open311::Endpoint::Service::Request::Update::mySociety->new(
        update_id => $id,
        status => lc $args->{status},
    );
    return $result;
}

sub _strip_args {
    my $args = shift;
    # Yes, just reversing what has just been done
    foreach my $k (keys %{$args->{attributes}}) {
        $args->{"attribute[$k]"} = $args->{attributes}{$k};
    }
    delete $args->{attributes};
}

=head2 get_service_request_updates

Fetches a list of updates from the backend.

=cut

sub get_service_request_updates {
    my ($self, $args) = @_;
    # Remove any blank parameters
    $args = { map { $_ => $args->{$_} } grep { length $args->{$_} } keys %$args };
    $args->{api_key} = $self->api_key;
    my $xml = $self->_request(GET => $self->updates_url, $args);
    my @updates;
    foreach (@{$xml->{request_update}}) {
        $_->{status} = lc $_->{status};
        $_->{status} =~ s/ /_/g; # Some backends use spaces
        $_->{updated_datetime} = $self->date_parser->parse_datetime($_->{updated_datetime});
        $_->{description} ||= "";
        my $update = Open311::Endpoint::Service::Request::Update::mySociety->new(%$_);
        push @updates, $update;
    }
    return @updates;
}

=head2 get_service_requests

Fetches a list of requests from the backend.

=cut

sub get_service_requests {
    my ($self, $args) = @_;
    $args->{api_key} = $self->api_key;
    my $xml = $self->_request(GET => "requests.xml", $args);
    my @requests;
    foreach (@{$xml->{request}}) {
        $_->{status} = lc $_->{status};
        $_->{status} =~ s/ /_/g; # Some backends use spaces
        $_->{updated_datetime} = $self->date_parser->parse_datetime($_->{updated_datetime});
        $_->{requested_datetime} = $self->date_parser->parse_datetime($_->{requested_datetime});
        $_->{latlong} = [ delete $_->{lat}, delete $_->{long} ];
        $_->{service} = Open311::Endpoint::Service->new(
            service_name => delete $_->{service_name},
            service_code => delete $_->{service_code},
        );
        my $request = Open311::Endpoint::Service::Request::ExtendedStatus->new(%$_);
        push @requests, $request;
    }
    return @requests;
}

1;

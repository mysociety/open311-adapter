package Integrations::SalesForceRest;

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
use MIME::Base64;

has 'endpoint_url' => (
    is => 'ro',
    default => sub { $_[0]->config->{endpoint} || '' }
);

has 'credentials' => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my $key = $self->config->{private_key};
        my $key_content = path(__FILE__)->parent(4)->realpath->child('keys')->child($key)->slurp;

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
);

has 'requests_endpoint' => (
    is => 'ro',
    default => sub { shift->endpoint_url . 'sobjects/Case'; }
);

has 'services_endpoint' => (
    is => 'ro',
    default => sub { shift->endpoint_url . 'sobjects/Case/describe' }
);

has 'updates_endpoint' => (
    is => 'ro',
    default => sub { shift->endpoint_url . 'FixMyStreetUpdates' }
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

sub create_object {
    my ($self, $object_name, $args) = @_;

    my $response = $self->post($self->endpoint_url . 'sobjects/' . $object_name, encode_json($args));

    return $response->{id};
}

sub post_request {
    my ($self, $service, $args) = @_;

    return $self->create_object('Case', $args);
}

sub post_user {
    my ($self, $account) = @_;

    my $id = $self->create_object( 'Account', $account );

    return $self->get($self->endpoint_url . "sobjects/Account/$id");
}

sub find_user {
    my ($self, $email) = @_;

    return $self->search( 'Account', 'PersonEmail,PersonContactId', $email );
}

sub post_attachment {
    my ($self, $id, $file) = @_;

    my $args = encode_json( {
        ParentId => $id,
        Name => $file->filename,
    } );

    my $uri = $self->endpoint_url . 'sobjects/Attachment';

    my $request = HTTP::Request::Common::POST(
        $uri,
        Content_Type => 'form-data',
        Content => [
            details => [ undef, undef, 'Content-Type' => 'application/json', Content => $args ],
            Body => [undef, $file->filename, 'Content-Type' => $file->header('Content-Type'), Content => $file->content]
        ]
    );
    $request->header(Authorization => 'Bearer ' . $self->credentials);

    my $response = $self->_send_request($request);

    return $response->{id};
}

sub get_case {
    my ($self, $case_id) = @_;

    return $self->get($self->endpoint_url . "sobjects/Case/$case_id");
}

sub get_services {
    my ($self, $args) = @_;

    my $case = $self->memcache->get('service_list');
    unless ($case) {
        $case = $self->get($self->services_endpoint);
        $self->memcache->set('service_list', $case, 1800);
    }

    my ($type, $subtype);
    for my $prop ( @{ $case->{fields} } ) {
        $type = $prop if $prop->{name} eq $self->config->{field_map}->{group};
        $subtype = $prop if $prop->{name} eq $self->config->{field_map}->{service_code};
        last if $type && $subtype;
    }

    my %assigned_types = ();
    my @services;
    for my $service (@{ $subtype->{picklistValues} }) {
        if ( $service->{validFor} ) {
            my $group_pos = _get_pos($service->{validFor});
            my @groups = map { $type->{picklistValues}->[$_]->{value} } @$group_pos;
            $service->{groups} = \@groups;
            $assigned_types{$_} = 1 for @groups;
        } else {
            $service->{groups} = [];
        }
        push @services, $service;
    }

    # make sure we include types that do not have any subtypes
    for my $service (@{ $type->{picklistValues} }) {
        next if $assigned_types{$service->{value}};
        $service->{groups} = [ $service->{value} ];
        push @services, $service;
    }

    return @services;
}

sub get_service {
    my ($self, $id, $args) = @_;

    my @services = $self->get_services($args);

    my $service;

    for ( @services ) {
        if ( $_->{value} eq $id ) {
            $service = $_;
            last;
        }
    }

    return $service;
}

sub search {
    my ($self, $object, $field, $term) = @_;

    my $results = $self->get(
        sprintf(
            '%sparameterizedSearch/?q=%s&sobject=%s&%s.fields=%s',
            $self->endpoint_url,
            $term,
            $object,
            $object,
            $field
        )
    );

    return $results;
}

# Salesforce uses a base 64 encoded bitmap to link second level items in
# dependent dropdowns, which this is decoding. The top level types a
# sub type are part of are represented by encoding the position in the
# type array in a string of 0 and 1s with 1s being the place in the type
# array that the parent type is. This is then encoded to bytes and then
# base 64 encoded.
sub _get_pos {
    my $s = shift;

    my $bytes = decode_base64($s);
    my $len = length($bytes) * 8;
    my $pos_map = unpack("B$len", $bytes);
    my @pos;

    for (my $pos=0; $pos<length $pos_map; $pos++) {
        push @pos, $pos if substr($pos_map, $pos, 1) == 1;
    }

    return \@pos;
}
1;

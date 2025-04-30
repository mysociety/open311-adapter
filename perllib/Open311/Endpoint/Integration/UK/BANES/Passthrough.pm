=head1 NAME

Open311::Endpoint::Integration::UK::BANES::Passthrough - Bath and North East Somerset Passthrough backend

=head1 SUMMARY

This is the BANES-specific Passthrough integration. It follows Open311
standards except requires a bearer token to be passed rather than an
api token

=cut

package Open311::Endpoint::Integration::UK::BANES::Passthrough;

use Moo;
extends 'Open311::Endpoint::Integration::Passthrough';

use Types::Standard ':all';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'www.banes.gov.uk';
    return $class->$orig(%args);
};

has bearer_details => (is => 'ro');

=head2 identifier_types

Add an identifier_types attribute to duplicate the UK.pm service_code validation
so the mocking in the test can remain shallow

=cut

has '+identifier_types' => (
    is => 'lazy',
    isa => HashRef[Any],
    default => sub {
    return {
        service_code => { type => '/open311/regex', pattern => qr/^ [&,\.\w_\- \@\/\(\)]+ $/ax },
        };
    }
);

=head2 service

BANES are not providing services or service calls for their own open311 backend.
All service requests should be sent, so we generate an artificial service
that permits the service request to be sent, but maintains the open311 flow.

=cut

sub services { () }

sub service {
    my ($self, $service_id, $args) = @_;

    my $service = Open311::Endpoint::Service->new(service_code => $service_id);

    my $attribute = Open311::Endpoint::Service::Attribute->new(
        code => $service_id,
        datatype => 'string',
    );
    push @{ $service->attributes }, $attribute;

    return $service;
};

=head2 _request

Rather than using an api key, we need to get a bearer token for authorisation
and set the Bearer header.

Also munge params - jurisdiction_id is not expected and we want to make
the service code the same as the Confirm code now it's been established
it's being sent to the Passthrough

=cut

around _request => sub {
    my ($orig, $self, $method, $url, $params) = @_;

    delete $params->{jurisdiction_id};

    if ($method eq 'POST' && $url !~ /api\/token/ ) {
        $params = { 'Content' => $params, 'Authorization' => 'Bearer ' . $self->_get_bearer_token()->content };
    };

    return $self->$orig($method, $url, $params);
};

sub _get_bearer_token {
    my $self = shift;

    my $bearer_details = $self->bearer_details;

    my $params = {
        username => $bearer_details->{username},
        password => $bearer_details->{password},
    };

    my $url = $bearer_details->{url};

    return $self->ua->post($url, $params);
};

1;

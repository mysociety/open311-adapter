=head1 NAME

Open311::Endpoint::Integration::UK::Bristol::Passthrough - Bristol Passthrough backend

=head1 SUMMARY

This is the Bristol-specific Passthrough integration. It is a standard
Open311 server.

=cut

package Open311::Endpoint::Integration::UK::Bristol::Passthrough;

use Moo;
extends 'Open311::Endpoint::Integration::Passthrough';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'www.bristol.gov.uk';
    return $class->$orig(%args);
};

around post_service_request_update => sub {
    my ($orig, $self, $args) = @_;
    # Bristol's endpoint gets confused if it receives a service_code on an update
    delete $args->{service_code};
    return $self->$orig($args);
};

1;

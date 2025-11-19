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

=over 4

=item * Remove service_code when posting update, as Bristol's endpoint gets confused if it receives one

=cut

around post_service_request_update => sub {
    my ($orig, $self, $args) = @_;
    delete $args->{service_code};
    $args->{description} = 'No update text' unless $args->{description};
    return $self->$orig($args);
};

=item * Ignore the update returned for every update we post

=back

=cut

around get_service_request_updates => sub {
    my ($orig, $self, $args) = @_;

    my @updates = $self->$orig($args);
    @updates = grep {
        $_->description ne 'A citizen has provided a follow-up to the original enquiry.'
    } @updates;
    return @updates;
};

1;

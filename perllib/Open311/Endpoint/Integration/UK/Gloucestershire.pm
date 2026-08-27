package Open311::Endpoint::Integration::UK::Gloucestershire;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ( $orig, $class, %args ) = @_;
    $args{jurisdiction_id} = 'gloucestershire_confirm';
    return $class->$orig(%args);
};

=head2 post_service_request_update

If we receive an update with the by_reporter flag set, change the status
so that it uses a different code when sent to Confirm.

=cut

around post_service_request_update => sub {
    my ($orig, $self, $args) = (@_);

    if ($args->{status} eq 'OPEN' && $args->{attributes}{by_reporter}) {
        $args->{override_status_code} = $self->forward_status_mapping->{OPEN_REPORTER};
    }

    return $self->$orig($args);
};

1;

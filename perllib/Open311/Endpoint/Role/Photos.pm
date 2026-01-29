package Open311::Endpoint::Role::Photos;

use Moo::Role;
no warnings 'illegalproto';

around dispatch_request => sub {
    my ($orig, $self, @args) = @_;
    my @dispatch = $self->$orig(@args);
    return (
        @dispatch,

        # Plural to prevent clashing with previous 'photo/completion' path.
        sub (GET + /photos + ?*) {
            my ($self, $args) = @_;
            $self->get_photo( $args );
        },

        # Kept for legacy when these were called
        # 'completion photos'.
        sub (GET + /photo/completion + ?*) {
            my ($self, $args) = @_;
            $self->get_photo( $args );
        },

    );
};

sub get_photo {
    my ($self, $args) = @_;
    $self->_call('get_photo', $args->{jurisdiction_id}, $args)
        or [ 400, [ 'Content-Type', 'text/plain' ], [ 'Bad request' ] ];
}


1;

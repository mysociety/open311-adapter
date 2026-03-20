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

# Handle being given a multi's jurisdiction_id directly
sub get_photo {
    my ($self, $args) = @_;
    my $jurisdiction_id = $args->{jurisdiction_id};

    foreach ($self->plugins) {
        if ($_->jurisdiction_id eq $jurisdiction_id) {
            return $_->get_photo($args);
        }
        if ($_->isa('Open311::Endpoint::Integration::Multi')) {
            foreach ($_->plugins) {
                if ($_->jurisdiction_id eq $jurisdiction_id) {
                    return $_->get_photo($args);
                }
            }
        }
    }

    [ 400, [ 'Content-type', 'text/plain' ], [ 'Bad request' ] ];
}

1;

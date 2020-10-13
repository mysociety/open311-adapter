package Open311::Endpoint::Role::CompletionPhotos;

use Moo::Role;
no warnings 'illegalproto';

around dispatch_request => sub {
    my ($orig, $self, @args) = @_;
    my @dispatch = $self->$orig(@args);
    return (
        @dispatch,

        sub (GET + /photo/completion + ?*) {
            my ($self, $args) = @_;
            $self->get_completion_photo( $args );
        },
    );
};

sub get_completion_photo {
    my ($self, $args) = @_;
    $self->_call('get_completion_photo', $args->{jurisdiction_id}, $args)
        or [ 400, [ 'Content-type', 'text/plain' ], [ 'Bad request' ] ];
}


1;

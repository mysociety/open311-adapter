package Open311::Endpoint::Integration::UK::Shropshire;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'shropshire_confirm';
    return $class->$orig(%args);
};

around process_service_request_args => sub {
    my ($orig, $self, $args) = (@_);

    my $ret = $self->$orig($args);

    if (my $poc = delete $args->{attributes}{contributed_by}) {
        $ret->{point_of_contact_code} = 'CSC';
    }

    return $ret;
};

1;

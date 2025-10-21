=head1 NAME

Open311::Endpoint::Integration::UK::Shropshire - Shropshire integration set-up

=head1 SYNOPSIS

Shropshire has a Confirm integration.

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Shropshire;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'shropshire_confirm';
    return $class->$orig(%args);
};

=head2 process_service_request_args

If the report was made by staff, we use a different point of contact code.

=cut

around process_service_request_args => sub {
    my ($orig, $self, $args) = (@_);

    my $ret = $self->$orig($args);

    if (my $poc = delete $args->{attributes}{contributed_by}) {
        $ret->{point_of_contact_code} = 'CSC';
    }

    return $ret;
};

1;

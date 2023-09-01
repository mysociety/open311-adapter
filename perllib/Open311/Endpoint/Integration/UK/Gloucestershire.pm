package Open311::Endpoint::Integration::UK::Gloucestershire;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ( $orig, $class, %args ) = @_;
    $args{jurisdiction_id} = 'gloucestershire_confirm';
    return $class->$orig(%args);
};

sub process_service_request_args {
    my $self = shift;
    my $args = $self->SUPER::process_service_request_args(shift);

    # Swap the contents of the description and location fields
    my $for_location = $args->{description};
    $args->{description} = $args->{location};
    $args->{location} = $for_location;

    return $args;
}

1;

package Open311::Endpoint::Integration::UK::Camden::ConfirmTrees;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

use Open311::Endpoint::Service::UKCouncil::Confirm;

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Confirm'
);

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'camden_confirm_trees';
    return $class->$orig(%args);
};

sub process_service_request_args {
    my $self = shift;
    my $args = $self->SUPER::process_service_request_args(shift);

    $args->{location} = $args->{location} . '; ' . $args->{attributes}->{closest_address};

    return $args;
}

1;

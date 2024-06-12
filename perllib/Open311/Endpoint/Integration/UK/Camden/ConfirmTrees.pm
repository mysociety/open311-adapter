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

1;

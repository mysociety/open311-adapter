package Open311::Endpoint::Integration::UK::Rutland::Confirm;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

use Open311::Endpoint::Service::UKCouncil::Confirm;

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'rutland_confirm';
    return $class->$orig(%args);
};

1;

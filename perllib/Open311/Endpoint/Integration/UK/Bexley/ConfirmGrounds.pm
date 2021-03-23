package Open311::Endpoint::Integration::UK::Bexley::ConfirmGrounds;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

use Open311::Endpoint::Service::UKCouncil::BexleyConfirm;

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::BexleyConfirm'
);

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bexley_confirm_grounds';
    return $class->$orig(%args);
};

1;

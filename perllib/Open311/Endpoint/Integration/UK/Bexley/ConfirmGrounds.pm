package Open311::Endpoint::Integration::UK::Bexley::ConfirmGrounds;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bexley_confirm_grounds';
    return $class->$orig(%args);
};

use Integrations::Confirm::BexleyGrounds;

has integration_class => (
    is => 'ro',
    default => 'Integrations::Confirm::BexleyGrounds'
);

1;

package Open311::Endpoint::Integration::UK::Essex;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'essex_confirm';
    return $class->$orig(%args);
};

use Integrations::Confirm::Essex;

has integration_class => (
    is => 'ro',
    default => 'Integrations::Confirm::Essex'
);

1;

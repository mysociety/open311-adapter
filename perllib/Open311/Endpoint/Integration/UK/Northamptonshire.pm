package Open311::Endpoint::Integration::UK::Northamptonshire;

use Moo;
extends 'Open311::Endpoint::Integration::Alloy';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'northamptonshire_alloy';
    return $class->$orig(%args);
};

use Integrations::Alloy::Northamptonshire;

has integration_class => (
    is => 'ro',
    default => 'Integrations::Alloy::Northamptonshire'
);

1;

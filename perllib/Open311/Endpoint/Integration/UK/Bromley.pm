package Open311::Endpoint::Integration::UK::Bromley;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bromley_confirm';
    return $class->$orig(%args);
};

use Integrations::Confirm::Bromley;

has integration_class => (
    is => 'ro',
    default => 'Integrations::Confirm::Bromley'
);

1;

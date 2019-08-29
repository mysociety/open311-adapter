package Open311::Endpoint::Integration::UK::Bexley::Confirm;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bexley_confirm';
    return $class->$orig(%args);
};

use Integrations::Confirm::Bexley;

has integration_class => (
    is => 'ro',
    default => 'Integrations::Confirm::Bexley'
);

1;

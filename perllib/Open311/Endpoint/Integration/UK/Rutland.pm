package Open311::Endpoint::Integration::UK::Rutland;
use parent 'Open311::Endpoint::Integration::SalesForce';

use Moo;

use Integrations::SalesForce::Rutland;

has jurisdiction_id => (
    is => 'ro',
    default => 'rutland',
);

sub integration_class { 'Integrations::SalesForce::Rutland' }

1;

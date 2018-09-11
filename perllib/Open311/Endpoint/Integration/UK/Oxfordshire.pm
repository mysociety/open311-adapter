package Open311::Endpoint::Integration::UK::Oxfordshire;
use parent 'Open311::Endpoint::Integration::WDM';

use Moo;

use Integrations::WDM::Oxfordshire;

has jurisdiction_id => (
    is => 'ro',
    default => 'oxfordshire',
);

sub integration_class { 'Integrations::WDM::Oxfordshire' }

1;

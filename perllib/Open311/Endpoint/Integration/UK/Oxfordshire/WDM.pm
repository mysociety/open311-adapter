package Open311::Endpoint::Integration::UK::Oxfordshire::WDM;

use Moo;
extends 'Open311::Endpoint::Integration::WDM';

has jurisdiction_id => (
    is => 'ro',
    default => 'oxfordshire_wdm',
);

1;

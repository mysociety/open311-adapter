package Open311::Endpoint::Integration::UK::Oxfordshire;
use parent 'Open311::Endpoint::Integration::WDM';

use Moo;

has jurisdiction_id => (
    is => 'ro',
    default => 'oxfordshire',
);

1;

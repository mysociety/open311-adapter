package Open311::Endpoint::Integration::UK::EastSussex;
use parent 'Open311::Endpoint::Integration::SalesForceRest';

use Moo;

has jurisdiction_id => (
    is => 'ro',
    default => 'eastsussex_salesforce',
);

1;

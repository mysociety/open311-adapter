package Open311::Endpoint::Integration::UK::CentralBedfordshire;

# use SOAP::Lite +trace => [ qw/method debug/ ];

use Moo;
extends 'Open311::Endpoint::Integration::Symology';

has jurisdiction_id => (
    is => 'ro',
    default => 'centralbedfordshire_symology',
);

1;

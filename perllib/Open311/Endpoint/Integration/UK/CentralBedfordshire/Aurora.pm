package Open311::Endpoint::Integration::UK::CentralBedfordshire::Aurora;

use Moo;
extends 'Open311::Endpoint::Integration::Aurora';

has jurisdiction_id => (
    is => 'ro',
    default => 'centralbedfordshire_aurora',
);

1;

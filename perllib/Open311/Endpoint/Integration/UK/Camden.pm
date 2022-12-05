package Open311::Endpoint::Integration::UK::Camden;

# use SOAP::Lite +trace => [ qw/method debug/ ];

use Moo;
extends 'Open311::Endpoint::Integration::Symology';

use Open311::Endpoint::Service::UKCouncil::Symology;

has jurisdiction_id => (
    is => 'ro',
    default => 'camden_symology',
);

# Updates from FMS should always have a GN11 code, meaning "Customer called"
sub event_action_event_type { ''}

1;

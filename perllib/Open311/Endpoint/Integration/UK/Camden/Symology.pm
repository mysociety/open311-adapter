package Open311::Endpoint::Integration::UK::Camden::Symology;

# use SOAP::Lite +trace => [ qw/method debug/ ];

use Moo;
extends 'Open311::Endpoint::Integration::Symology';

use Open311::Endpoint::Service::UKCouncil::Symology;

has jurisdiction_id => (
    is => 'ro',
    default => 'camden_symology',
);

1;

package Open311::Endpoint::Integration::UK::Peterborough::Ezytreev;

use Moo;
extends 'Open311::Endpoint::Integration::Ezytreev';

has jurisdiction_id => (
    is => 'ro',
    default => 'peterborough_ezytreev',
);

sub get_service_requests { return (); }

__PACKAGE__->run_if_script;

package Open311::Endpoint::Integration::UK::Peterborough::Bartec;

use Moo;
extends 'Open311::Endpoint::Integration::Bartec';

has jurisdiction_id => (
    is => 'ro',
    default => 'peterborough_bartec',
);

__PACKAGE__->run_if_script;

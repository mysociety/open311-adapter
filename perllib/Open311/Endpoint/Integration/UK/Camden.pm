package Open311::Endpoint::Integration::UK::Camden;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Camden'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'camden',
);

__PACKAGE__->run_if_script;

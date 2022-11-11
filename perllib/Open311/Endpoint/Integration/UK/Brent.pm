package Open311::Endpoint::Integration::UK::Brent;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Brent'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'brent',
);

__PACKAGE__->run_if_script;

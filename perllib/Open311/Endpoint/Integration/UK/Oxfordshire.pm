package Open311::Endpoint::Integration::UK::Oxfordshire;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Oxfordshire'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'oxfordshire',
);

has integration_without_prefix => (
    is => 'ro',
    default => 'WDM',
);

sub service_request_content {
    '/open311/service_request_extended'
}

__PACKAGE__->run_if_script;

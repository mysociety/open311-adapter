package Open311::Endpoint::Integration::UK::Hackney;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => [ 'Open311::Endpoint::Integration::UK::Hackney' ],
    except => [ 'Open311::Endpoint::Integration::UK::Hackney::Base' ],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'hackney',
);

sub service_request_content {
    '/open311/service_request_extended'
}

has integration_without_prefix => (
    is => 'ro',
    default => 'Highways',
);

__PACKAGE__->run_if_script;

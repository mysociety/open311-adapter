=head1 NAME

Open311::Endpoint::Integration::UK::Bromley - Bromley integration set-up

=head1 SYNOPSIS

Bromley will have multiple backends, so is set up as a subclass
of the Multi integration.

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Bromley;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Bromley'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'bromley',
);

=pod

Bromley was previously only an Echo backend in open311-adapter, so we
maintain its categories/IDs without any backend prefix.

=cut

has integration_without_prefix => (
    is => 'ro',
    default => 'Echo',
);

__PACKAGE__->run_if_script;

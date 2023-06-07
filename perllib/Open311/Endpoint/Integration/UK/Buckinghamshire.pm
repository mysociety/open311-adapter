=head1 NAME

Open311::Endpoint::Integration::UK::Buckinghamshire - Buckinghamshire integration set-up

=head1 SYNOPSIS

Buckinghamshire has multiple backends, so is set up as a subclass
of the Multi integration. It was originally Alloy, but Abavus was added

=cut

package Open311::Endpoint::Integration::UK::Buckinghamshire;

use Moo;
extends 'Open311::Endpoint::Integration::Multi';

use Module::Pluggable
    search_path => ['Open311::Endpoint::Integration::UK::Buckinghamshire'],
    instantiate => 'new';

has jurisdiction_id => (
    is => 'ro',
    default => 'buckinghamshire',
);

=pod

Buckinghamshire was previously only an Alloy backend in open311-adapter, so we
maintain its categories/IDs without any backend prefix as any updates on pre-multi
reports will be looking for the id without the prefix

=cut

has integration_without_prefix => (
    is => 'ro',
    default => 'Alloy',
);

__PACKAGE__->run_if_script;

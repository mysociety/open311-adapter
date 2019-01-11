package Integrations::Alloy::Northamptonshire;

use Path::Tiny;
use Moo;
extends 'Integrations::Alloy';
with 'Role::Config';

has config_filename => (
    is => 'ro',
    default => 'northamptonshire_alloy',
);

sub _build_config_file {
    my $self = shift;
    path(__FILE__)->parent(4)->realpath->child('conf/council-' . $self->config_filename . '.yml');
}

1;

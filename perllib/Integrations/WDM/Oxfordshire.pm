package Integrations::WDM::Oxfordshire;

use Path::Tiny;
use Moo;
extends 'Integrations::WDM';
with 'Role::Config';

has config_filename => (
    is => 'ro',
    default => 'oxfordshire_wdm',
);

sub _build_config_file {
    my $self = shift;
    # uncoverable statement
    path(__FILE__)->parent(4)->realpath->child('conf/council-' . $self->config_filename . '.yml');
}

1;

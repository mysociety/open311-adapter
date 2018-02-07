package Role::Config;

use Path::Tiny;
use YAML;
use Moo::Role;

has config_file => (
    is => 'lazy',
    coerce => sub { path($_[0]) },
);

sub _build_config_file {
    path(__FILE__)->parent(3)->realpath->child('conf/general.yml');
}

has config => (
    is => 'lazy',
    isa => sub { die "not a hashref" unless ref $_[0] eq 'HASH' },
);

sub _build_config {
    my $self = shift;
    my $conf = YAML::LoadFile($self->config_file);
    return $conf;
}

1;

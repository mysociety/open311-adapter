package Role::Config;

use Path::Tiny;
use YAML::XS qw(LoadFile);
use Moo::Role;

has config_filename => (
    is => 'rw',
    default => '',
);

has config_file => (
    is => 'lazy',
    coerce => sub { path($_[0]) },
);

sub _build_config_file {
    my $self = shift;
    my $path = path(__FILE__)->parent(3)->realpath->child('conf');
    if ($self->config_filename) {
        $path->child('council-' . $self->config_filename . '.yml');
    } else {
        $path->child('general.yml');
    }
}

has config => (
    is => 'lazy',
    isa => sub { die "not a hashref" unless ref $_[0] eq 'HASH' },
);

sub _build_config {
    my $self = shift;
    local $YAML::XS::Boolean = "JSON::PP";
    return {} if !$self->config_file->is_file && $ENV{TEST_MODE};
    my $conf = LoadFile($self->config_file);
    return $conf;
}

1;

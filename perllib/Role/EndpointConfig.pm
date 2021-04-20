# Very similar to Role::Config, but to be used by subclasses of Web::Simple
# (such as any Open311::Endpoint::Integration::...) as that sets a config
# attribute

package Role::EndpointConfig;

use Path::Tiny;
use YAML::XS qw(LoadFile);
use Moo::Role;

has config_file => (
    is => 'lazy',
    coerce => sub { path($_[0]) },
);

sub _build_config_file {
    my $self = shift;
    my $path = path(__FILE__)->parent(3)->realpath->child('conf');
    $path->child('council-' . $self->jurisdiction_id . '.yml');
}

has endpoint_config => (
    is => 'lazy',
    isa => sub { die "not a hashref" unless ref $_[0] eq 'HASH' },
);

sub _build_endpoint_config {
    my $self = shift;
    return {} if !$self->config_file->is_file && $ENV{TEST_MODE};
    my $conf = LoadFile($self->config_file);
    return $conf;
}

1;

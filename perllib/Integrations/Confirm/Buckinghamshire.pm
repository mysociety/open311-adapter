package Integrations::Confirm::Buckinghamshire;

use Moo;
extends 'Integrations::Confirm';
with 'Role::Config';

sub endpoint_url { $_[0]->config->{CONFIRM}->{Buckinghamshire}->{url} }

sub credentials {
    my $config = $_[0]->config->{CONFIRM}->{Buckinghamshire};
    return (
        $config->{username},
        $config->{password},
        $config->{tenant_id}
    );
}

sub server_timezone { 'Europe/London' }

has '+memcache_namespace' => (
    default => 'buckinghamshire_confirm',
);

1;

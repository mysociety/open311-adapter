package Role::Memcached;

use Moo::Role;
use Cache::Memcached;

has memcache_namespace => (
    is => 'lazy',
    default => sub {
        my $namespace = $_[0]->config->{memcached_namespace} || 'open311adapter';
        $namespace .= ':' . $_[0]->config_filename . ':';
        return $namespace;
    }
);

has memcache => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my $servers = $ENV{TEST_MODE} ? [] : [ '127.0.0.1:11211' ];
        new Cache::Memcached {
            'servers' => $servers,
            'namespace' => $self->memcache_namespace,
            'debug' => 0,
            'compress_threshold' => 10_000,
        };
    },
);

1;

package Role::Memcached;

use Moo::Role;
use Cache::Memcached;

has memcache_namespace  => (
    is => 'lazy',
    default => sub { $_[0]->config_filename }
);

has memcache => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my $namespace = 'open311adapter:' . $self->memcache_namespace . ':';
        my $servers = $ENV{TEST_MODE} ? [] : [ '127.0.0.1:11211' ];
        new Cache::Memcached {
            'servers' => $servers,
            'namespace' => $namespace,
            'debug' => 0,
            'compress_threshold' => 10_000,
        };
    },
);

1;

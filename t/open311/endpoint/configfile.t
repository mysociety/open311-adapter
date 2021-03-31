use strict; use warnings;

BEGIN {
    $ENV{TEST_MODE} = 1;

    package Foo;
    use Moo;
    with 'Open311::Endpoint::Role::ConfigFile';

    around BUILDARGS => sub {
        my ($orig, $class, %args) = @_;
        $args{jurisdiction_id} = 'foo';
        return $class->$orig(%args);
    };

    has foo => ( is => 'ro', default => 'foo' );
}

package main;
use Test::More;

is +Foo->new->foo, 
    'foo', 'sanity';
is +Foo->new( foo => 'bar')->foo,
    'bar', 'override';
is +Foo->new( config_file => 't/open311/endpoint/config1.yml' )->foo,
    'baz', 'with config';
is +Foo->new( config_file => 't/open311/endpoint/config1.yml', foo => 'qux' )->foo,
    'qux', 'with config, overridden';

done_testing;

package Integrations::Confirm::AberdeenshireDummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling("aberdeenshire_defect_attributes.yml")->stringify }

package Open311::Endpoint::Integration::UK::AberdeenshireDummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Aberdeenshire';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'aberdeenshire_defect_attributes_dummy';
    $args{config_file} = path(__FILE__)->sibling("aberdeenshire_defect_attributes.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::AberdeenshireDummy');

package main;

use strict;
use warnings;

use Test::More;

BEGIN { $ENV{TEST_MODE} = 1; }

my $endpoint = Open311::Endpoint::Integration::UK::AberdeenshireDummy->new;

subtest "Only uses the first photo" => sub {
    my @photos = (
        {
            URL => '1',
            Name => '1.jpg',
            Date => DateTime->now->subtract(days => 1),
        },
        {
            URL => '2',
            Name => '2.jpg',
            Date => DateTime->now->subtract(days => 2),
        },
        {
            URL => '3',
            Name => '3.jpg',
            Date => DateTime->now->subtract(days => 3),
        },
    );
    my @filtered = $endpoint->filter_photos_graphql(@photos);

    is @filtered, 1;
    is $filtered[0]->{URL}, 3;
};

done_testing;

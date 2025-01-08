package Integrations::Agile::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Agile';
sub _build_config_file { path(__FILE__)->sibling('agile.yml')->stringify }

package Open311::Endpoint::Integration::Agile::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Agile';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'agile_dummy';
    $args{config_file} = path(__FILE__)->sibling('agile.yml')->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Agile::Dummy');

package main;

use strict;
use warnings;

use JSON::MaybeXS;
use Test::MockModule;
use Test::More;

BEGIN { $ENV{TEST_MODE} = 1; }

my $endpoint = Open311::Endpoint::Integration::Agile::Dummy->new;
my $integration = Test::MockModule->new('Integrations::Agile');
$integration->mock( api_call => sub {
    my ( $self, %args ) = @_;

    my $action = $args{action};

    if ( $action eq 'isaddressfree' ) {
        if ( $args{data}{UPRN} eq '123_no_sub' ) {
            return {
                IsFree  => 'True',
                EndDate => undef,
            };

        } elsif ( $args{data}{UPRN} eq '234_has_sub' ) {
            return {
                IsFree  => 'False',
                EndDate => undef,
            };
        }

    } elsif ( $action eq 'signup' ) {
        if ( $args{data}{ActionReference} eq 'bad_data' ) {
            die 'Unhandled error';

        } else {
            return {
                CustomerExternalReference => 'GWIT-CUST-001',
                CustomerReference => 'GWIT-CUST-001',
                ServiceContractReference => 'GW-SERV-001',
            };
        }
    }
} );

subtest 'GET services' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), [
        {
            group        => "Waste",
            service_code => "garden_subscription",
            description  => "Garden Subscription",
            keywords     => "waste_only",
            type         => "realtime",
            service_name => "Garden Subscription",
            metadata     => "true"
        }
    ], 'correct json returned';
};

subtest 'GET service' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services/garden_subscription.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    my %defaults = (
        automated => 'hidden_field',
        datatype => 'string',
        datatype_description => '',
        required => 'false',
        variable => 'true',
    );

    is_deeply decode_json( $res->content ), {
        service_code => 'garden_subscription',
        attributes   => [
            {   %defaults,
                automated   => 'server_set',
                code        => 'fixmystreet_id',
                description => 'external system ID',
                order       => 1,
                required    => 'true',
                variable    => 'false'
            },
            {   %defaults,
                code                 => 'uprn',
                description          => 'UPRN reference',
                order                => 2,
            },
            {   %defaults,
                code                 => 'current_containers',
                description          => 'Number of current containers',
                order                => 3,
            },
            {   %defaults,
                code                 => 'new_containers',
                description          => 'Number of new containers',
                order                => 4,
            },
            {   %defaults,
                code                 => 'payment_method',
                description          => 'Payment method: credit card or direct debit',
                order                => 5,
            }
        ],
    }, 'correct json returned';
};

subtest 'successfully subscribe to garden waste' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'garden_subscription',
        first_name => 'Bob',
        last_name => 'Mould',
        description => 'Want leafy bin now',
        lat => 51,
        long => -1,
        'attribute[fixmystreet_id]' => 2000001,
        'attribute[uprn]' => '123_no_sub',
        'attribute[current_containers]' => 1,
        'attribute[new_containers]' => 2,
        'attribute[payment_method]' => 'credit_card',
        'attribute[PaymentCode]' => 'payment_123',
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), [ {
        service_request_id => 'GW-SERV-001',
    } ], 'correct json returned';
};

subtest 'try to subscribe to garden waste when already subscribed' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'garden_subscription',
        first_name => 'Bob',
        last_name => 'Mould',
        description => 'Want leafy bin now',
        lat => 51,
        long => -1,
        'attribute[fixmystreet_id]' => 2000001,
        'attribute[uprn]' => '234_has_sub',
        'attribute[current_containers]' => 1,
        'attribute[new_containers]' => 2,
        'attribute[payment_method]' => 'credit_card',
        'attribute[PaymentCode]' => 'payment_123',
    );

    my $content = decode_json($res->content);
    is $content->[0]{code}, 500;
    like $content->[0]{description}, qr/UPRN 234_has_sub already has a sub/,
        'Dies with error msg';
};

subtest 'handle unknown error' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'garden_subscription',
        first_name => 'Bob',
        last_name => 'Mould',
        description => 'Want leafy bin now',
        lat => 51,
        long => -1,
        'attribute[fixmystreet_id]' => 'bad_data',
        'attribute[uprn]' => '123_no_sub',
        'attribute[current_containers]' => 1,
        'attribute[new_containers]' => 2,
        'attribute[payment_method]' => 'credit_card',
        'attribute[PaymentCode]' => 'payment_123',
    );

    my $content = decode_json($res->content);
    is $content->[0]{code}, 500;
    like $content->[0]{description}, qr/Unhandled error/,
        'Dies with error msg';
};

done_testing;

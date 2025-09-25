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
    } elsif ( $action eq 'cancel' ) {
        return {
            Reference => 'GWIT2025-001-001',
            Status => 'Hold',
        };
    }
} );

subtest 'GET services' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    my @got = sort { $a->{service_code} cmp $b->{service_code} }
        @{ decode_json( $res->content ) };

    is_deeply \@got, [
        {
            group        => "Waste",
            service_code => "garden_subscription",
            description  => "Garden Subscription",
            keywords     => "waste_only",
            type         => "realtime",
            service_name => "Garden Subscription",
            metadata     => "true"
        },
        {
            group        => "Waste",
            service_code => "garden_subscription_cancel",
            description  => "Cancel Garden Subscription",
            keywords     => "waste_only",
            type         => "realtime",
            service_name => "Cancel Garden Subscription",
            metadata     => "true"
        },
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
                code                 => 'property_id',
                description          => 'Property ID',
                order                => 3,
            },
            {   %defaults,
                code                 => 'total_containers',
                description          => 'Total number of requested containers',
                order                => 4,
            },
            {   %defaults,
                code                 => 'current_containers',
                description          => 'Number of current containers',
                order                => 5,
            },
            {   %defaults,
                code                 => 'new_containers',
                description          => 'Number of new containers (total requested minus current)',
                order                => 6,
            },
            {   %defaults,
                code                 => 'payment_method',
                description          => 'Payment method: credit card or direct debit',
                order                => 7,
            },
            {   %defaults,
                code                 => 'payment',
                description          => 'Payment amount in pence',
                order                => 8,
            },
            {   %defaults,
                code                 => 'pro_rata',
                description          => 'Payment amount in pence for subscription amendments',
                order                => 9,
            },
            {   %defaults,
                code                 => 'reason',
                description          => 'Cancellation reason',
                order                => 10,
            },
            {   %defaults,
                code                 => 'due_date',
                description          => 'Cancellation date',
                order                => 11,
            },
            {   %defaults,
                code                 => 'customer_external_ref',
                description          => 'Customer external ref',
                order                => 12,
            },
            {   %defaults,
                code                 => 'direct_debit_reference',
                description          => 'Direct debit reference',
                order                => 13,
            },
            {   %defaults,
                code                 => 'direct_debit_start_date',
                description          => 'Direct debit initial payment date',
                order                => 14,
            },
            {   %defaults,
                code                 => 'type',
                description          => 'Denotes whether subscription request is a renewal or not',
                order                => 15,
            },
            {   %defaults,
                code                 => 'renew_as_new_subscription',
                description          => 'Denotes a renewal that is being made as a new subscription due to new (unverified) user',
                order                => 16,
            },
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
        'attribute[total_containers]' => 2,
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
        'attribute[total_containers]' => 2,
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
        'attribute[total_containers]' => 2,
        'attribute[payment_method]' => 'credit_card',
        'attribute[PaymentCode]' => 'payment_123',
    );

    my $content = decode_json($res->content);
    is $content->[0]{code}, 500;
    like $content->[0]{description}, qr/Unhandled error/,
        'Dies with error msg';
};

subtest 'successfully cancel a garden subscription' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'garden_subscription_cancel',
        lat => 51,
        long => -1,
        'attribute[fixmystreet_id]' => 2000002,
        'attribute[customer_external_ref]' => 'customer_ABC',
        'attribute[uprn]' => '234_has_sub',
        'attribute[reason]' => 'I used all my garden waste for a bonfire',
        'attribute[due_date]' => '01/01/2025',
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), [ {
        service_request_id => 'GWIT2025-001-001',
    } ], 'correct json returned';
};

subtest 'try to cancel when no subscription' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'garden_subscription_cancel',
        lat => 51,
        long => -1,
        'attribute[fixmystreet_id]' => 2000002,
        'attribute[customer_external_ref]' => 'customer_ABC',
        'attribute[uprn]' => '123_no_sub',
        'attribute[reason]' => 'I used all my garden waste for a bonfire',
        'attribute[due_date]' => '01/01/2025',
    );

    my $content = decode_json($res->content);
    is $content->[0]{code}, 500;
    like $content->[0]{description},
        qr/UPRN 123_no_sub does not have a subscription to be cancelled/,
        'Dies with error msg';
};

done_testing;

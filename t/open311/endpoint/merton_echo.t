package SOAP::Result;
use Object::Tiny qw(method result);

package Integrations::Echo::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Echo';
sub _build_config_file { path(__FILE__)->sibling("merton.yml")->stringify }

package Open311::Endpoint::Integration::UK::Merton::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Merton::Echo';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'merton_dummy';
    $args{config_file} = path(__FILE__)->sibling("merton.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Echo::Dummy');

package main;

use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use DateTime;
use Test::More;
use Test::MockModule;
use JSON::MaybeXS;

use constant EVENT_TYPE_MISSED => 'missed';
use constant EVENT_TYPE_ASSISTED => 1565;
use constant EVENT_TYPE_MISSED_REFUSE => 1566;
use constant EVENT_TYPE_MISSED_RECYCLING => 1568;
use constant EVENT_TYPE_SUBSCRIBE => 1638;
use constant EVENT_TYPE_BULKY => 1636;

my $soap_lite = Test::MockModule->new('SOAP::Lite');
$soap_lite->mock(call => sub {
    # This is called when a test below makes a SOAP call, along with the data
    # to be passed via SOAP to the server. We check the values here, then pass
    # back a mocked result.
    my ($cls, @args) = @_;
    my $method = $args[0]->name;
    if ($method eq 'PostEvent') {
        my @params = ${$args[3]->value}->value;
        if (@params == 5) {
            my $client_ref = $params[1]->value;
            my $event_type = $params[3]->value;
            my $service_id = $params[4]->value;
            like $client_ref, qr/MRT-200012[4-8]|bulky-cc/;
            if ($client_ref eq 'MRT-2000124') {
                is $event_type, EVENT_TYPE_MISSED_REFUSE;
                is $service_id, 405;
                my @data = ${$params[0]->value}->value->value;
                my @bin = ${$data[0]->value}->value;
                is $bin[0]->value, 2000;
                is $bin[1]->value, 1;
            } elsif ($client_ref eq 'MRT-2000125') {
                is $event_type, EVENT_TYPE_MISSED_RECYCLING;
                is $service_id, 408;
                my @data = ${$params[0]->value}->value->value;
                my @paper = ${$data[0]->value}->value;
                is $paper[0]->value, 2002;
                is $paper[1]->value, 1;
            } elsif ($event_type eq EVENT_TYPE_BULKY) {
                my @data = ${$params[0]->value}->value->value;
                my @payment = ${$data[0]->value}->value;
                is $payment[0]->value, 1011;
                is $payment[1]->value, 1;
                my $val = $client_ref eq 'bulky-cc' ? 2 : 1;
                @payment = ${$data[1]->value}->value;
                is $payment[0]->value, 1013;
                is $payment[1]->value, $val;
                if ($client_ref eq 'bulky-cc') { # Also check items
                    is @data, 3, 'Has item present in the data';
                }
            } elsif ($event_type eq EVENT_TYPE_ASSISTED) {
                my @data = ${$params[0]->value}->value->value;
                my @payment = ${$data[0]->value}->value;
                is $payment[0]->value, 3001;
                is $payment[1]->value, 'Notes';
                my $val = $client_ref eq 'bulky-cc' ? 2 : 1;
                @payment = ${$data[1]->value}->value;
                is $payment[0]->value, 3002;
                is $payment[1]->value, 1;
            }
        } elsif (@params == 2) {
            is $params[0]->value, '123pay';
            my @data = ${$params[1]->value}->value->value;
            my @payment = ${$data[0]->value}->value;
            is $payment[1]->value, 27409;
            my @child = ${$payment[0]->value}->value->value;
            my @ref = ${$child[0]->value}->value;
            is $ref[0]->value, 27410;
            is $ref[1]->value, 'ABC';
            @ref = ${$child[1]->value}->value;
            is $ref[0]->value, 27411;
            is $ref[1]->value, '34.56';
        } else {
            is @params, 'UNKNOWN';
        }
        return SOAP::Result->new(result => {
            EventGuid => '1234',
        });
    } elsif ($method eq 'GetEvent') {
        if (${(${$args[3]->value}->value)[2]->value}->value->value eq 'bulky_1') {
            return SOAP::Result->new(result => {
                Id => 'echo_bulky',
                EventTypeId => EVENT_TYPE_BULKY,
                EventStateId => 4002,
            });
        } else {
            return SOAP::Result->new(result => {
                Id => '123pay',
                EventTypeId => EVENT_TYPE_BULKY,
                EventStateId => 4002,
            });
        }
    } elsif ($method eq 'GetEventType') {
        my @params = ${$args[3]->value}->value;
        my $id = ${$params[2]->value}->value->value->value;
        if ($id eq EVENT_TYPE_BULKY) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1011, Name => "Payment Type" },
                    { Id => 1012, Name => "Payment Taken By" },
                    { Id => 1013, Name => "Payment Method" },
                    { Id => 1020, Name => "Bulky Collection",
                        ChildDatatypes => { ExtensibleDatatype => [
                            { Id => 1021, Name => "Bulky Items" },
                            { Id => 1022, Name => "Notes" },
                        ] },
                    },
                ] },
            });
        } elsif ($id eq EVENT_TYPE_SUBSCRIBE) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1004, Name => "Subscription Details",
                        ChildDatatypes => { ExtensibleDatatype => [
                            { Id => 1005, Name => "Quantity" },
                            { Id => 1007, Name => "Containers" },
                        ] },
                    },
                ] },
            });
        } elsif ($id eq EVENT_TYPE_MISSED_REFUSE) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1008, Name => "Notes" },
                    { Id => 2000, Name => "Refuse Bin" },
                    { Id => 2001, Name => "Container Mix" },
                    { Id => 2002, Name => "Paper" },
                ] },
            });
        } elsif ($id eq EVENT_TYPE_MISSED_RECYCLING) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1008, Name => "Notes" },
                    { Id => 2000, Name => "Refuse Bin" },
                    { Id => 2001, Name => "Container Mix" },
                    { Id => 2002, Name => "Paper" },
                ] },
            });
        } elsif ($id eq EVENT_TYPE_ASSISTED) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 3001, Name => "Crew Notes" },
                    { Id => 3002, Name => "Add to Assist" },
                    { Id => 3003, Name => "Remove from Assist" },
                ] },
            });
        }
    } elsif ($method eq 'PerformEventAction') {
        my @params = ${$args[3]->value}->value;
        if (@params, 3) {
            return SOAP::Result->new(result => { EventActionGuid => 'ABC' });
        }
        is @params, 2, 'No notes';
        my $ref = ${(${$params[1]->value}->value)[2]->value}->value->value->value;
        my $actiontype_id = $params[0]->value;
        is $actiontype_id, 8;
        return SOAP::Result->new(result => { EventActionGuid => 'ABC' });
    } else {
        is $method, 'UNKNOWN';
    }
});

use Open311::Endpoint::Integration::UK::Merton::Dummy;

my $endpoint = Open311::Endpoint::Integration::UK::Merton::Dummy->new;

my @params = (
    POST => '/requests.json',
    api_key => 'test',
    first_name => 'Bob',
    last_name => 'Mould',
    description => "This is the details",
    lat => 51,
    long => -1,
    'attribute[uprn]' => 1000001,
);

subtest "POST missed bin OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_MISSED,
        'attribute[fixmystreet_id]' => 2000124,
        'attribute[service_id]' => 2238,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST missed mixed+paper OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_MISSED,
        'attribute[fixmystreet_id]' => 2000125,
        'attribute[service_id]' => 2240,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST subscription request OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_SUBSCRIBE,
        'attribute[fixmystreet_id]' => 2000126,
        'attribute[Subscription_Details_Containers]' => 26, # Garden Bin
        'attribute[Subscription_Details_Quantity]' => 1,
        'attribute[Request_Type]' => 1,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST bulky request card payment OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_BULKY,
        'attribute[fixmystreet_id]' => 2000127,
        'attribute[payment_method]' => 'credit_card',
        'attribute[client_reference]' => 'bulky-cc',
        'attribute[Bulky_Collection_Bulky_Items]' => "11",
        'attribute[Bulky_Collection_Notes]' => "Vanity dressing table",
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST Bulky Collection update OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'test',
        updated_datetime => '2023-09-01T19:00:00+01:00',
        service_request_id => 'bulky_1',
        update_id => 456,
        status => 'OPEN',
        description => 'Amend Bulky collection',
        first_name => 'Bob',
        last_name => 'Mould',
        'attribute[Bulky_Collection_Items]' => '83::6',
        'attribute[Exact_Location]' => 'in the middle of the drive',
        'attribute[Bulky_Collection_Notes]' => '::Very heavy',
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "update_id" => 'BLANK',
        } ], 'correct json returned';
};

subtest "POST a successful payment" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'test',
        updated_datetime => '2023-09-01T19:00:00+01:00',
        service_request_id => '123pay',
        update_id => 456,
        status => 'OPEN',
        description => 'Payment confirmed, reference ABC, amount £34.56',
        'attribute[payments]' => 'ABC|34.56',
        first_name => 'Bob',
        last_name => 'Mould',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "update_id" => 'BLANK',
        } ], 'correct json returned';
};

subtest "POST a cancellation" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'test',
        updated_datetime => '2023-09-01T19:00:00+01:00',
        service_request_id => '123cancel',
        update_id => 456,
        status => 'OPEN',
        description => 'Booking cancelled by customer',
        first_name => 'Bob',
        last_name => 'Mould',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "update_id" => 'ABC',
        } ], 'correct json returned';
};

subtest "POST assisted collection OK" => sub {
    my $res = $endpoint->run_test_request(@params,
        service_code => EVENT_TYPE_ASSISTED . '-add',
        'attribute[service_id]' => 2238,
        'attribute[fixmystreet_id]' => 2000128,
        'attribute[Crew_Notes]' => 'Notes',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

done_testing;

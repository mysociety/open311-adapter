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

use constant EVENT_TYPE_MISSED => 3145;
use constant EVENT_TYPE_ASSISTED => 3200;
use constant EVENT_TYPE_SUBSCRIBE => 3159;
use constant EVENT_TYPE_BULKY => 3130;

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
                is $event_type, EVENT_TYPE_MISSED;
                is $service_id, 1067;
            } elsif ($client_ref eq 'MRT-2000125') {
                is $event_type, EVENT_TYPE_MISSED;
                is $service_id, 1075;
            } elsif ($event_type eq EVENT_TYPE_BULKY) {
                my @dataa = ${$params[0]->value}->value->value;
                my @datab = ${$dataa[0]->value}->value->value;
                my @datac = ${$datab[0]}->value->value;
                my @item = ${$datac[0]->value}->value;
                is $item[0]->value, 1021;
                is $item[1]->value, 11;
                @item = ${$datac[1]->value}->value;
                is $item[0]->value, 1022;
                is $item[1]->value, 'Vanity dressing table';
            } elsif ($event_type eq EVENT_TYPE_ASSISTED) {
                my @data = ${$params[0]->value}->value->value;
                my @action = ${$data[0]->value}->value;
                is $action[0]->value, 3001;
                is $action[1]->value, '1';
                my @notes = ${$data[1]->value}->value;
                is $notes[0]->value, 3002;
                is $notes[1]->value, 'Notes';
                my @start = ${$data[2]->value}->value;
                is $start[0]->value, 3003;
                is $start[1]->value, DateTime->today(time_zone => "Europe/London")->dmy('/');
                is $data[3], undef;
            }
        } elsif (@params == 2) {
            is $params[0]->value, '123pay';
            my @data = ${$params[1]->value}->value->value;
            my @ref = ${$data[0]->value}->value;
            is $ref[0]->value, 57236;
            is $ref[1]->value->value, 'ABC'; # Is wrapped to make it a string
            my @amount = ${$data[1]->value}->value;
            is $amount[0]->value, 57237;
            is $amount[1]->value->value, '34.56';
        } else {
            is @params, 'UNKNOWN';
        }
        return SOAP::Result->new(result => {
            EventGuid => '1234',
        });
    } elsif ($method eq 'GetEvent') {
        return SOAP::Result->new(result => {
            Id => '123pay',
            EventTypeId => EVENT_TYPE_BULKY,
            EventStateId => 4002,
        });
    } elsif ($method eq 'GetEventType') {
        my @params = ${$args[3]->value}->value;
        my $id = ${$params[2]->value}->value->value->value;
        if ($id eq EVENT_TYPE_BULKY) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1020, Name => "TEM - Bulky Collection",
                        ChildDatatypes => { ExtensibleDatatype => [
                            { Id => 1021, Name => "Item" },
                            { Id => 1022, Name => "Description" },
                        ] },
                    },
                ] },
            });
        } elsif ($id eq EVENT_TYPE_SUBSCRIBE) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1004, Name => "Subscription Details",
                        ChildDatatypes => { ExtensibleDatatype => [
                            { Id => 1005, Name => "Paid Container Quantity" },
                            { Id => 1007, Name => "Paid Container Type" },
                        ] },
                    },
                ] },
            });
        } elsif ($id eq EVENT_TYPE_MISSED) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1008, Name => "Notes" },
                ] },
            });
        } elsif ($id eq EVENT_TYPE_ASSISTED) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 3001, Name => "Action" },
                    { Id => 3002, Name => "Exact Location" },
                    { Id => 3003, Name => "Start Date" },
                    { Id => 3004, Name => "End Date" },
                ] },
            });
        }
    } elsif ($method eq 'PerformEventAction') {
        my @params = ${$args[3]->value}->value;
        is @params, 2, 'No notes';
        my $ref = ${(${$params[1]->value}->value)[2]->value}->value->value->value;
        my $actiontype_id = $params[0]->value;
        is $actiontype_id, 518;
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
        'attribute[service_id]' => 1067,
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
        'attribute[service_id]' => 1075,
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
        'attribute[Paid_Container_Type]' => 39, # Garden Bin
        'attribute[Paid_Container_Quantity]' => 1,
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
        'attribute[TEM_-_Bulky_Collection_Item]' => "11",
        'attribute[TEM_-_Bulky_Collection_Description]' => "Vanity dressing table",
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
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
        status => 'CANCELLED',
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
        'attribute[service_id]' => 1067,
        'attribute[fixmystreet_id]' => 2000128,
        'attribute[Exact_Location]' => 'Notes',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

done_testing;

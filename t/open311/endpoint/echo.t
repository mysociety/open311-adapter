package SOAP::Result;
use Object::Tiny qw(method result);

package Integrations::Echo::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Echo';
sub _build_config_file { path(__FILE__)->sibling("echo.yml")->stringify }

package Open311::Endpoint::Integration::Echo::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Echo';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'echo_dummy';
    $args{config_file} = path(__FILE__)->sibling("echo.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Echo::Dummy');

package main;

use strict;
use warnings;
use utf8;

BEGIN { $ENV{TEST_MODE} = 1; }

use Test::More;
use Test::MockModule;
use SOAP::Lite;

use JSON::MaybeXS;

use constant EVENT_TYPE_MISSED => 2096;
use constant EVENT_TYPE_REQUEST => 2104;
use constant EVENT_TYPE_ENQUIRY => 2148;
use constant EVENT_TYPE_SUBSCRIBE => 2106;

my $soap_lite = Test::MockModule->new('SOAP::Lite');
$soap_lite->mock(call => sub {
    # This is called when a test below makes a SOAP call, along with the data
    # to be passed via SOAP to the server. We check the values here, then pass
    # back a mocked result.
    my ($cls, @args) = @_;
    my $method = $args[0]->name;
    if ($method eq 'PostEvent') {
        my @params = ${$args[3]->value}->value;

        my $client_ref = $params[1]->value;
        like $client_ref, qr/^FMS-200012[34]$/;
        my $multi_request = $client_ref eq 'FMS-2000124';

        my $event_type = $params[3]->value;
        my $service_id = $params[4]->value;
        if ($event_type == EVENT_TYPE_REQUEST) {
            is $service_id, 547, 'Service ID overriden for a new container request';
        }

        # Check the UPRN has been included
        my @event_object = ${${$params[2]->value}->value->value}->value;
        is $event_object[0]->value, 'Source';
        my @object_ref = ${$event_object[1]->value}->value;
        is $object_ref[0]->value, 'Uprn';
        is $object_ref[1]->value, 'PointAddress';
        my $uprn = ${$object_ref[2]->value}->value->value->value->value;

        my @data = ${$params[0]->value}->value->value;
        if ($event_type == EVENT_TYPE_MISSED) {
            is $uprn, 1000001;
            is @data, 3, 'Name and source is only extra data';
        } elsif ($multi_request) {
            is @data, 5, 'Name, source and two container stuff';
        } elsif ($event_type == EVENT_TYPE_SUBSCRIBE) {
            if ( $uprn == 1000001 || $uprn == 1000003 ) {
                is @data, 5, 'Name, source, type and subscription request';
            } elsif ( $uprn == 1000002 ) {
                is @data, 6, 'Name, source, type, subscription request and container stuff';
            }
        } else {
            is $uprn, 1000001;
            is @data, 4, 'Name, source and (container stuff or notes)';
        }
        my @first_name = ${$data[0]->value}->value;
        is $first_name[0]->value, 1001;
        is $first_name[1]->value, 'Bob';
        my @last_name = ${$data[1]->value}->value;
        is $last_name[0]->value, 1002;
        is $last_name[1]->value, 'Mould';
        my @source = ${$data[2]->value}->value;
        is $source[0]->value, 1003;
        is $source[1]->value, 2;
        if ($event_type == EVENT_TYPE_REQUEST) {
            # Compare the Container Stuff entry and its children
            my @notes = ${$data[3]->value}->value;
            is $notes[1]->value, 1004;
            my @children = ${$notes[0]->value}->value->value;
            my @child = ${$children[0]->value}->value;
            is $child[0]->value, 1005;
            is $child[1]->value, 2;
            @child = ${$children[1]->value}->value;
            is $child[0]->value, 1006;
            is $child[1]->value, 7;
            @child = ${$children[2]->value}->value;
            is $child[0]->value, 1007;
            is $child[1]->value, 12;
            if ($multi_request) {
                @notes = ${$data[4]->value}->value;
                is $notes[1]->value, 1004;
                @children = ${$notes[0]->value}->value->value;
                @child = ${$children[0]->value}->value;
                is $child[0]->value, 1005;
                is $child[1]->value, 2;
                @child = ${$children[1]->value}->value;
                is $child[0]->value, 1006;
                is $child[1]->value, 1;
                @child = ${$children[2]->value}->value;
                is $child[0]->value, 1007;
                is $child[1]->value, 12;
            }
        } elsif ($event_type == EVENT_TYPE_ENQUIRY) {
            my @notes = ${$data[3]->value}->value;
            is $notes[0]->value, 1008;
            is $notes[1]->value, 'These are some notes 🎉';

            # Check serialisation as well
            my $envelope = $cls->serializer->envelope(method => $method, @notes);
            like $envelope, qr/These are some notes 🎉/;
        } elsif ($event_type == EVENT_TYPE_SUBSCRIBE) {
            my @sub_request = ${$data[3]->value}->value;
            is $sub_request[1]->value, 1004;
            my @children = ${$sub_request[0]->value}->value->value;
            my @quantity = ${$children[0]->value}->value;
            is $quantity[0]->value, 1005;
            if ($uprn == 1000003) {
                is $quantity[1]->value, 0;
            } else {
                is $quantity[1]->value, 2;
            }
            my @container_type = ${$children[1]->value}->value;
            is $container_type[0]->value, 1007;
            is $container_type[1]->value, 44;
            if ($uprn == 1000002) {
                my @container_request = ${$data[4]->value}->value;
                is $container_request[1]->value, 1009;
                my @children = ${$container_request[0]->value}->value->value;
                my @quantity = ${$children[0]->value}->value;
                is $quantity[0]->value, 1005;
                is $quantity[1]->value, 1;
                my @container_type = ${$children[1]->value}->value;
                is $container_type[0]->value, 1007;
                is $container_type[1]->value, 44;
                my @sub_type = ${$data[5]->value}->value;
                is $sub_type[0]->value, 1010;
                is $sub_type[1]->value, 1;
            } else {
                my @sub_type = ${$data[4]->value}->value;
                is $sub_type[0]->value, 1010;
                is $sub_type[1]->value, 1;
            }
        }

        return SOAP::Result->new(result => {
            EventGuid => '1234',
        });
    } elsif ($method eq 'GetEventType') {
        my @params = ${$args[3]->value}->value;
        my $event_type = ${$params[2]->value}->value->value->value;
        if ( $event_type == EVENT_TYPE_SUBSCRIBE ) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1001, Name => "First Name" },
                    { Id => 1002, Name => "Surname" },
                    { Id => 1003, Name => "Source" },
                    { Id => 1004, Name => "Subscription Details",
                        ChildDatatypes => { ExtensibleDatatype => [
                            { Id => 1005, Name => "Quantity" },
                            { Id => 1007, Name => "Container Type" },
                        ] },
                    },
                    { Id => 1009, Name => "Container Request",
                        ChildDatatypes => { ExtensibleDatatype => [
                            { Id => 1005, Name => "Quantity" },
                            { Id => 1007, Name => "Container Type" },
                        ] },
                    },
                    { Id => 1010, Name => "Type" },
                    { Id => 1008, Name => "Notes" },
                ] },
            });
        } else {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1001, Name => "First Name" },
                    { Id => 1002, Name => "Surname" },
                    { Id => 1003, Name => "Source" },
                    { Id => 1004, Name => "Container Stuff",
                        ChildDatatypes => { ExtensibleDatatype => [
                            { Id => 1005, Name => "Quantity" },
                            { Id => 1006, Name => "Reason" },
                            { Id => 1007, Name => "Container Type" },
                        ] },
                    },
                    { Id => 1008, Name => "Notes" },
                ] },
            });
        }
    } elsif ($method eq 'PerformEventAction') {
        my @params = ${$args[3]->value}->value;
        my $action_type_id = $params[0]->value;
        is $action_type_id, 3;
        my @data = ${${$params[1]->value}->value->value}->value;
        my $text = $data[1]->value;
        is $text, 'This is the text of the update';
        my @ref = ${$params[2]->value}->value;
        is $ref[1]->value, 'Event';
        is ${$ref[2]->value}->value->value->value, 'test-12345';
        return SOAP::Result->new(result => {
            EventActionGuid => 'action-1234',
        });
    } else {
        is $method, 'UNKNOWN';
    }
});

use Open311::Endpoint::Integration::Echo::Dummy;

my $endpoint = Open311::Endpoint::Integration::Echo::Dummy->new;

subtest "GET services" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), [
   {
      "keywords" => "",
      "service_name" => "Request new container",
      "service_code" => EVENT_TYPE_REQUEST,
      "metadata" => "true",
      "type" => "realtime",
      "description" => "Request new container",
      "group" => "Waste"
   },
   {
      "keywords" => "",
      "service_name" => "Garden Subscription",
      "service_code" => EVENT_TYPE_SUBSCRIBE,
      "metadata" => "true",
      "type" => "realtime",
      "description" => "Garden Subscription",
      "group" => "Waste"
   },
   {
      "description" => "Gate not closed",
      "group" => "Waste",
      "metadata" => "true",
      "type" => "realtime",
      "service_code" => "2118",
      "service_name" => "Gate not closed",
      "keywords" => ""
   },
   {
      "service_name" => "Waste spillage",
      "service_code" => "2119",
      "keywords" => "",
      "group" => "Waste",
      "description" => "Waste spillage",
      "metadata" => "true",
      "type" => "realtime"
   },
   {
      "service_name" => "General Enquiry",
      "service_code" => EVENT_TYPE_ENQUIRY,
      "keywords" => "",
      "description" => "General Enquiry",
      "group" => "Waste",
      "type" => "realtime",
      "metadata" => "true"
   },
   {
      "service_name" => "Assisted collection add",
      "service_code" => "2149-add",
      "keywords" => "",
      "description" => "Assisted collection add",
      "group" => "Waste",
      "type" => "realtime",
      "metadata" => "true"
   },
   {
      "service_name" => "Assisted collection remove",
      "service_code" => "2149-remove",
      "keywords" => "",
      "description" => "Assisted collection remove",
      "group" => "Waste",
      "type" => "realtime",
      "metadata" => "true"
   },
   {
      "service_name" => "Report missed collection",
      "service_code" => "missed",
      "keywords" => "",
      "description" => "Report missed collection",
      "group" => "Waste",
      "type" => "realtime",
      "metadata" => "true"
   },
    ], 'correct json returned';
};

subtest "GET service" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services/missed.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), {
      "service_code" => "missed",
      "attributes" => [
          { code => 'uprn', order => 1, required => 'false', variable => 'true', datatype => 'string', datatype_description => '', automated => 'hidden_field', description => 'UPRN reference' },
          { code => 'service_id', order => 2, required => 'false', variable => 'true', datatype => 'string', datatype_description => '', automated => 'server_set', description => 'Service ID' },
          { code => 'fixmystreet_id', order => 3, required => 'true', variable => 'false', datatype => 'string', datatype_description => '', automated => 'server_set', description => 'external system ID' },
      ],
    }, 'correct json returned';
};

subtest "POST missed collection OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'missed',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[service_id]' => 536, # Communal container mix
        'attribute[uprn]' => 1000001,
        'attribute[fixmystreet_id]' => 2000123,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST new request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => EVENT_TYPE_REQUEST,
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[uprn]' => 1000001,
        'attribute[fixmystreet_id]' => 2000123,
        'attribute[Container_Type]' => 12, # Black Box (Paper)
        'attribute[Quantity]' => 2,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST new multi-request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => EVENT_TYPE_REQUEST,
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[uprn]' => 1000001,
        'attribute[fixmystreet_id]' => 2000124,
        'attribute[Container_Type]' => 12, # Black Box (Paper)
        'attribute[Quantity]' => 2,
        'attribute[Reason]' => '7::1',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST general enquiry OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => EVENT_TYPE_ENQUIRY,
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[service_id]' => 531, # Domestic refuse
        'attribute[uprn]' => 1000001,
        'attribute[fixmystreet_id]' => 2000123,
        'attribute[Notes]' => "These are some notes 🎉",
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST update OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'test',
        update_id => '678',
        updated_datetime => '2020-06-18T12:00:00Z',
        service_request_id => 'test-12345',
        status => 'OPEN',
        description => 'This is the text of the update',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "update_id" => 'action-1234',
        } ], 'correct json returned';
};

subtest "POST subscription request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => EVENT_TYPE_SUBSCRIBE,
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[uprn]' => 1000001,
        'attribute[fixmystreet_id]' => 2000123,
        'attribute[Subscription_Details_Container_Type]' => 44, # Garden Waste
        'attribute[Subscription_Details_Quantity]' => 2,
        'attribute[Type]' => 1,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST subscription request with containter request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => EVENT_TYPE_SUBSCRIBE,
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[uprn]' => 1000002,
        'attribute[fixmystreet_id]' => 2000123,
        'attribute[Subscription_Details_Container_Type]' => 44, # Garden Waste
        'attribute[Subscription_Details_Quantity]' => 2,
        'attribute[Container_Request_Container_Type]' => 44, # Garden Waste
        'attribute[Container_Request_Quantity]' => 1,
        'attribute[Type]' => 1,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

subtest "POST subscription request with zero containers OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => EVENT_TYPE_SUBSCRIBE,
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[uprn]' => 1000003,
        'attribute[fixmystreet_id]' => 2000123,
        'attribute[Subscription_Details_Container_Type]' => 44, # Garden Waste
        'attribute[Subscription_Details_Quantity]' => 0,
        'attribute[Type]' => 1,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => '1234',
        } ], 'correct json returned';
};

done_testing;

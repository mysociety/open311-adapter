package Integrations::Surrey::Boomi::Dummy;
use Path::Tiny;
use Moo;
use HTTP::Response;
use HTTP::Headers;
use Test::More;
use Test::MockModule;
use JSON::MaybeXS qw(encode_json decode_json);
use URI;

extends 'Integrations::Surrey::Boomi';

my $lwp = Test::MockModule->new('LWP::UserAgent');
my $lwp_counter = 0;

$lwp->mock(request => sub {
    my ($ua, $req) = @_;

    if ($req->uri =~ /upsertHighwaysTicket$/) {
        is $req->method, 'POST', "Correct method used";
        is $req->uri, 'http://localhost/ws/simple/upsertHighwaysTicket';
        my $content = decode_json($req->content);
        is_deeply $content, {
        "location" => {
            "longitude" => "0.1",
            "northing" => "2",
            "latitude" => "50",
            "easting" => "1"
        },
        "subject" => "Pot hole on road",
        "description" => "Big hole in the road",
        "status" => "open",
        "integrationId" => "Integration.1",
        "requester" => {
            "email" => 'test@example.com',
            "fullName" => "Bob Mould",
            "phone" => undef
        },
        "customFields" => [
            {
                "values" => [
                    "Roads"
                ],
                "id" => "category"
            },
            {
                "values" => [
                    "Pothole"
                ],
                "id" => "subCategory"
            },
            {
                "id" => "fixmystreet_id",
                "values" => [
                    "1"
                ]
            }
        ]
        };
        return HTTP::Response->new(200, 'OK', [], encode_json({"ticket" => { system => "Zendesk", id => 1234 }}));
    }
});

sub _build_config_file { path(__FILE__)->sibling("surrey_boomi.yml")->stringify };

package Open311::Endpoint::Integration::Boomi::Dummy;
use Path::Tiny;
use Moo;
use HTTP::Response;
use HTTP::Headers;

extends 'Open311::Endpoint::Integration::Boomi';

has integration_class => (
    is => 'ro',
    default => 'Integrations::Surrey::Boomi::Dummy',
);

package main;

use strict; use warnings;

use utf8;

use Test::More;
use Test::MockTime ':all';

use Open311::Endpoint;
use Path::Tiny;
use Open311::Endpoint::Integration::Boomi;
use Integrations::Surrey::Boomi;
use Open311::Endpoint::Service::UKCouncil;
use LWP::UserAgent;
use JSON::MaybeXS qw(encode_json decode_json);

BEGIN { $ENV{TEST_MODE} = 1; }

my $surrey_endpoint = Open311::Endpoint::Integration::Boomi::Dummy->new(
    jurisdiction_id => 'surrey_boomi',
    config_file => path(__FILE__)->sibling("surrey_boomi.yml")->stringify,
);

subtest "Check empty services structure" => sub {
    my @services = $surrey_endpoint->services;

    is scalar @services, 0, "Zero categories found";
};

subtest "GET Service List" => sub {
    my $res = $surrey_endpoint->run_test_request( GET => '/services.json' );
    ok $res->is_success, 'json success';
    is_deeply decode_json($res->content), [];
};

subtest "POST report" => sub {
    set_fixed_time('2023-05-01T12:00:00Z');
    my $res = $surrey_endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'surrey_boomi',
        api_key => 'api-key',
        service_code => 'potholes',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'title: Pothole on road detail: Big hole in the road',
        media_url => ['https://localhost/one.jpeg?123', 'https://localhost/two.jpeg?123'],
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'Big hole in the road',
        'attribute[title]' => 'Pot hole on road',
        'attribute[report_url]' => 'http://localhost/1',
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[category]' => 'Pothole',
        'attribute[group]' => 'Roads',
        'attribute[fixmystreet_id]' => 1,
        );
    is $res->code, 200;
    is_deeply decode_json($res->content), [{
        service_request_id => 'Zendesk_1234',
    }];
    restore_time();
};

done_testing;

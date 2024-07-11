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
                "easting" => "1",
                "usrn" => "31200342",
                "streetName" => "Cockshot Hill",
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
                    "id" => "Q7",
                    "values" => [
                        "T1", "T3"
                    ]
                },
                {
                    "id" => "RM1",
                    "values" => [
                        "RM1B"
                    ]
                },
                {
                    "id" => "fixmystreet_id",
                    "values" => [
                        "1"
                    ]
                },
                {
                    "id" => "report_url",
                    "values" => [
                        "http://localhost/report/1"
                    ]
                },
            ],
            "attachments" => [
                {
                    "url" => "http://localhost/photo/one.jpeg",
                    "fileName" => "1.jpeg",
                    "base64" => "/9j/4AAQSkZJRgABAQAAAAAAAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkI\nCQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/wAALCAABAAEBAREA/8QAFAABAAAAAAAA\nAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==\n",
                },
            ]
        };
        return HTTP::Response->new(200, 'OK', [], encode_json({"ticket" => { system => "Zendesk", id => 1234 }}));
    } elsif ($req->uri =~ /getHighwaysTicketUpdates/) {
        is $req->method, 'GET', "Correct method used";


        return HTTP::Response->new(200, 'OK', [], encode_json({
            "executionId" => "execution-7701f16b-036c-4e6e-8e14-998f81f5b6b8-2024.06.27",
            "results" => [
                {
                    "confirmEnquiryStatusLog" => {
                        "loggedDate" => "2024-05-01T09:07:47.000Z",
                        "logNumber" => 11,
                        "statusCode" => "5800",
                        "enquiry" => {
                            "enquiryNumber" => 129293,
                            "externalSystemReference" => "2929177"
                        }
                    },
                    "fmsReport" => {
                        "status" => {
                            "state" => "Closed",
                            "label" => "Enquiry closed"
                        }
                    }
                },
                {
                    "confirmEnquiryStatusLog" => {
                        "loggedDate" => "2024-05-01T09:10:41.000Z",
                        "logNumber" => 7,
                        "statusCode" => "3200",
                        "enquiry" => {
                            "enquiryNumber" => 132361,
                            "externalSystemReference" => "2939061"
                        }
                    },
                    "fmsReport" => {
                        "status" => {
                            "state" => "Action scheduled",
                            "label" => "Assessed - scheduling a repair within 5 Working Days"
                        }
                    }
                },
            ]
        }));
    } elsif ($req->uri eq 'http://localhost/photo/one.jpeg') {
        my $image_data = path(__FILE__)->sibling('files')->child('test_image.jpg')->slurp;
        my $response = HTTP::Response->new(200, 'OK', []);
        $response->header('Content-Disposition' => 'attachment; filename="1.jpeg"');
        $response->header('Content-Type' => 'image/jpeg');
        $response->content($image_data);
        return $response;
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
        media_url => ['http://localhost/photo/one.jpeg'],
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'Big hole in the road',
        'attribute[title]' => 'Pot hole on road',
        'attribute[report_url]' => 'http://localhost/report/1',
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[category]' => 'Pothole',
        'attribute[group]' => 'Roads',
        'attribute[fixmystreet_id]' => 1,
        'attribute[RM1]' => "RM1B",
        'attribute[USRN]' => "31200342",
        'attribute[ROADNAME]' => "Cockshot Hill",
        'attribute[Q7]' => "T1",
        'attribute[Q7]' => "T3",
        );
    is $res->code, 200;
    is_deeply decode_json($res->content), [{
        service_request_id => 'Zendesk_1234',
    }];
    restore_time();
};

subtest "GET Service Request Updates" => sub {
    my $res = $surrey_endpoint->run_test_request(
        GET => '/servicerequestupdates.json?jurisdiction_id=surrey_boomi&api_key=api-key&start_date=2024-05-01T09:00:00Z&end_date=2024-05-01T10:00:00Z',
    );
    is $res->code, 200;
    is_deeply decode_json($res->content), [
       {
          "description" => "Enquiry closed",
          "media_url" => "",
          "service_request_id" => "Zendesk_2929177",
          "status" => "closed",
          "update_id" => "2929177_11",
          "updated_datetime" => "2024-05-01T09:07:47Z",
       },
       {
          "description" => "Assessed - scheduling a repair within 5 Working Days",
          "media_url" => "",
          "service_request_id" => "Zendesk_2939061",
          "status" => "action_scheduled",
          "update_id" => "2939061_7",
          "updated_datetime" => "2024-05-01T09:10:41Z",
       }
    ];
};

done_testing;

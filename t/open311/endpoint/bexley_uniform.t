package SOAP::Result;

use Object::Tiny qw(method result);

package main;

use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use Test::More;
use Test::MockModule;

use JSON::MaybeXS;

my $soap_lite = Test::MockModule->new('SOAP::Lite');
$soap_lite->mock(call => sub {
    # This is called when a test below makes a SOAP call, along with the data
    # to be passed via SOAP to the server. We check the values here, then pass
    # back a mocked result.
    my ($cls, @args) = @_;
    if ($args[0] eq 'LogonToConnector') {
        my @params = ${$args[1]->value}->value;
        is $params[1]->value, 'FMS';
        return SOAP::Result->new(result => {
            LogonSuccessful => 'true',
        });
    } elsif ($args[0] eq 'GetCnCodeList') {
        return SOAP::Result->new(result => {
            CodeList => {
                CnCode => [
                    { CodeValue => 'FLY', CodeText => 'Fly-tipping' },
                    { CodeValue => 'DFOUL', CodeText => 'Doggy fouling' },
                ]
            }
        });
    } elsif ($args[0] eq 'SubmitDogServiceRequest') {
        my @request = ${$args[1]->value}->value;
        is $request[1]->value, 'DFOUL';
        my @site_location = ${$request[2]->value}->value;
        foreach (@site_location) {
            is $_->value, 100 if $_->name eq 'MapEast';
        }
        my $photo_desc = "\n\n[ This report contains a photo, see: http://example.org/photo/1.jpeg ]";
        is $request[3]->value, "This is the details$photo_desc";
        return SOAP::Result->new(method => {
            ServiceRequestIdentification => {
                ReferenceValue => 1001,
            }
        });
    } elsif ($args[0] eq 'GetChangedServiceRequestRefVals') {
        my @request = $args[1]->value;
        is $request[0], '2019-09-25T00:00:00Z';
        return SOAP::Result->new(method => { RefVals => [
            { ReferenceValue => 1, RequestType => 'GENERAL' },
            { ReferenceValue => 2, RequestType => 'GENERAL' },
            { ReferenceValue => 3, RequestType => 'GENERAL' },
            { ReferenceValue => 4, RequestType => 'GENERAL' },
            { ReferenceValue => 5, RequestType => 'FOOD' },
        ] });
    } elsif ($args[0] eq 'GetGeneralServiceRequestByReferenceValue') {
        my @request = $args[1]->value;
        like $request[0], qr/^[1234]$/;
        my %cac = ( 1 => '', 2 => 'NFA', 3 => 'DUPR', 4 => 'NAP' );
        return SOAP::Result->new(result => {
            AdministrationDetails => {
                StatusCode => $request[0] == 1 ? '4_INV' : '8_CLO',
                ClosingActionCode => $cac{$request[0]},
            }
        });
    } else {
        is $args[0], '';
    }
});

my $integ = Test::MockModule->new('Integrations::Uniform');
$integ->mock(config => sub {
    {
        endpoint_url => 'http://bexley-uniform.example.org/',
    }
});

my $end = Test::MockModule->new('Open311::Endpoint::Integration::UK::Bexley::Uniform');
$end->mock(endpoint_config => sub {
    {
        username => 'FMS',
        service_whitelist => {
            DFOUL => { name => 'Dog fouling' },
            FLY => { name => 'Fly tipping' },
        },
    }
});

use Open311::Endpoint::Integration::UK::Bexley::Uniform;

my $endpoint = Open311::Endpoint::Integration::UK::Bexley::Uniform->new;

subtest "POST Dog fouling OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'DFOUL',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[easting]' => 100,
        'attribute[northing]' => 100,
        'attribute[fixmystreet_id]' => 123,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 1001
        } ], 'correct json returned';
};

subtest 'fetching an update' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.json?start_date=2019-09-25T00:00:00Z&end_date=2019-09-25T02:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is_deeply decode_json($res->content), [
        {
            "status" => "investigating",
            "media_url" => "",
            "service_request_id" => 1,
            "update_id" => "1_18a2ec4c",
            "updated_datetime" => "2019-09-25T02:00:00Z",
            "description" => ""
        }, {
            "status" => "no_further_action",
            "media_url" => "",
            "service_request_id" => 2,
            "update_id" => "2_dcad5b4f",
            "updated_datetime" => "2019-09-25T02:00:00Z",
            "description" => ""
        }, {
            "status" => "duplicate",
            "media_url" => "",
            "service_request_id" => 3,
            "update_id" => "3_73785740",
            "updated_datetime" => "2019-09-25T02:00:00Z",
            "description" => ""
        }, {
            "status" => "no_further_action",
            "media_url" => "",
            "service_request_id" => 4,
            "update_id" => "4_3fae3984",
            "updated_datetime" => "2019-09-25T02:00:00Z",
            "description" => ""
        }
    ], 'correct json returned';
};

done_testing;

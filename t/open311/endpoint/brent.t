package SOAP::Result;
use Object::Tiny qw(method result);

package main;
use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use JSON::MaybeXS;
use YAML::XS qw(LoadFile);
use Path::Tiny;
use File::Temp qw(tempfile);
use Test::More;
use Test::MockModule;
use Test::LongString;
use Test::MockTime ':all';
use Test::Exception;

# Set up

sub new_service {
    Open311::Endpoint::Service->new(description => $_[0], service_code => $_[0], service_name => $_[0]);
}

my $echo_int = Test::MockModule->new('Integrations::Echo');
$echo_int->mock('config', sub {
    my $cfg = path(__FILE__)->sibling('brent_echo.yml');
    my $config = LoadFile($cfg) or die $!;
    return $config;
});

my $echo = Test::MockModule->new('Open311::Endpoint::Integration::UK::Brent::Echo');
$echo->mock('BUILDARGS', sub {
    my $cls = shift;
    my $cfg = path(__FILE__)->sibling('brent_echo.yml');
    my $config = LoadFile($cfg) or die $!;
    return $echo->original('BUILDARGS')->($cls, %$config, @_);
});

my $symology = Test::MockModule->new('Open311::Endpoint::Integration::UK::Brent::Symology');
$symology->mock('_build_config_file', sub {
    path(__FILE__)->sibling('brent_symology.yml');
});

my $brent_integ = Test::MockModule->new('Integrations::Symology');
$brent_integ->mock(config => sub {
    {
        endpoint_url => 'http://www.example.org/',
        endpoint_username => 'ep',
        endpoint_password => 'password',
    }
});

my (undef, $atak_status_tracking_file) = tempfile(EXLOCK => 0);
my (undef, $atak_update_storage_file) = tempfile(EXLOCK => 0);

sub atak_config {
    {
        username => "user",
        password => "pass",
        api_url => "https://example.com/ords/hws/atak/v1",
        project_code => "C123",
        project_name => "LB BRENT",
        services => {
            PARK_LITTER_BIN_NEEDS_EMPTYING => {
                name => "Park litter bin needs emptying",
                group => "Parks and open spaces",
            },
            PARK_LITTERING => {
                name => "Parks littering",
                group => "Parks and open spaces",
            },
            PARK_FLY_TIPPING => {
                name => "Parks fly-tipping",
                group => "Parks and open spaces",
            },
        },
        max_issue_text_characters => 900,
        issue_status_tracking_file => $atak_status_tracking_file,
        update_storage_file => $atak_update_storage_file,
        issue_status_tracking_max_age_days => 365,
        update_storage_max_age_days => 365,
        atak_status_to_fms_status => {
            "Closed - Completed" => "fixed",
            "Closed - Out of scope" => "no_further_action",
            "Closed - Not found" => "closed",
            "Closed - Passed to Brent" => "internal_referral",
        },
    }
}

my $atak = Test::MockModule->new('Open311::Endpoint::Integration::UK::Brent::ATAK');
$atak->mock(endpoint_config => sub { return atak_config() });

my $atak_int = Test::MockModule->new('Integrations::ATAK');
$atak_int->mock(config => sub { return atak_config() });

my $atak_endpoint = Open311::Endpoint::Integration::UK::Brent::ATAK->new(jurisdiction_id => 'test');

use constant {
    REPORT_NSGREF => 0,
    REPORT_DATE => 1,
    REPORT_TIME => 2,
    REPORT_USER => 3,
    REPORT_REQUEST_TYPE => 4,
    REPORT_PRIORITY => 5,
    REPORT_AC1 => 6,
    REPORT_ACT2 => 7,
    REPORT_LOCATION => 8,
    REPORT_REF => 9,
    REPORT_DESC => 10,
    REPORT_EASTING => 11,
    REPORT_NORTHING => 12,
    REPORT_INWEB => 13,
    REPORT_SERVICECODE => 14,
    REPORT_NEXTACTION => 15,
    UPDATE_REPORT_ID => 123,
};

use constant {
    NSGREF => '123/4567',
};

use constant {
    NORTHING => 100,
    EASTING => 100,
};

my $soap_lite = Test::MockModule->new('SOAP::Lite');
$soap_lite->mock(call => sub {
    # This is called when a test below makes a SOAP call, along with the data
    # to be passed via SOAP to the server. We check the values here, then pass
    # back a mocked result.
    my ($cls, @args) = @_;
    if ($args[0] eq 'SendRequestAdditionalGroupAuthenticated') {
        is $args[1]->value, 'ep';
        is $args[2]->value, 'password';
        my @request = ${$args[4]->value}->value;
        is $request[REPORT_NSGREF]->value, NSGREF;
        my $next_action = Open311::Endpoint::Integration::UK::Brent::Symology->new->endpoint_config->{nsgref_to_action}{+NSGREF};
        is $request[REPORT_NEXTACTION]->value, $next_action; # Worked out automatically from 0
        is $request[REPORT_NORTHING]->value, NORTHING;
        my $photo_desc = "\n\n[ This report contains a photo, see: http://example.org/photo/1.jpeg ]";
        my $burnt = 'No';
        is $request[REPORT_DESC]->value, "This is the details$photo_desc\n\nBurnt out?: $burnt\n\nCar details: Details";
        is $request[REPORT_PRIORITY]->value, "P";
        is $request[REPORT_LOCATION]->value, 'Report title';
        return {
            StatusCode => 0,
            StatusMessage => 'Success',
            SendRequestResults => {
                SendRequestResultRow => {
                    RecordType => 2,
                    ConvertCRNo => 1001,
                }
            }
        };
    } elsif ($args[0] eq 'SendEventActionAuthenticated') {
        my @request = map { $_->value } ${$args[4]->value}->value;
        my $photo_desc = "\n\n[ This update contains a photo, see: http://example.org/photo/1.jpeg ]";
        my $report_id = $request[2];
        my $code = 'CHRR';
        is_deeply \@request, [ 'ServiceCode', 1001, $report_id, $code, '', 'FMS', "This is the update$photo_desc", undef ];
        return {
            StatusCode => 0,
            StatusMessage => 'Event Loaded',
            SendEventActionResults => {
                SendEventActionResultRow => {
                    RecordType => 2,
                }
            }
        };
    } elsif ($args[0]->name eq 'PostEvent') {
        my @params = ${$args[3]->value}->value;

        my $client_ref = $params[1]->value;
        like $client_ref, qr/^FMS-23[45]b?$/;

        my $event_type = $params[3]->value;
        my $service_id = $params[4]->value;

        if ($event_type =~ /^(935|943)/) {
            is $service_id, 277;
        } elsif ($event_type == 2891) {
            if ($client_ref eq 'FMS-235') {
                is $service_id, 265, 'Service id updated to missed recycling collection';
                my @data = ${$params[0]->value}->value->value;
                is @data, 2, 'Extra data present';
                my @bin = ${$data[0]->value}->value;
                my @bag = ${$data[1]->value}->value;
                is $bin[0]->value, 1003;
                is $bin[1]->value, 1, 'Recycling BIN has been ticked';
                is $bag[0]->value, 1004;
                is $bag[1]->value, 1, 'Recycling BOX has been ticked';
            } else {
                is $service_id, 262, 'Service id updated to missed refuse collection';
                my @data = ${$params[0]->value}->value->value;
                is @data, 2, 'Extra data is refuse BIN and refuse BAG';
                my @bin = ${$data[0]->value}->value;
                my @bag = ${$data[1]->value}->value;
                is $bin[0]->value, 1001;
                is $bin[1]->value, 1, 'Refuse BIN has been ticked';
                is $bag[0]->value, 1002;
                is $bag[1]->value, 1, 'Refuse BAG has been ticked';
            }
        } elsif ($event_type == 1159) {
            is $service_id, 317;
            my $c = 0;
            my @data = ${$params[0]->value}->value->value;
            my @name = ${$data[$c++]->value}->value;
            my @ref = ${$data[$c++]->value}->value;
            is $name[0]->value, 1001;
            is $name[1]->value, 'Bob', 'Name';
            is $ref[0]->value, 1009;
            is $ref[1]->value, 'PAY12345', 'Correct reference';
            if ($client_ref eq 'FMS-234b') {
                is @data, 5, 'Extra data right size';
                my @sack = ${$data[$c++]->value}->value;
                is $sack[0]->value, 21131;
                is $sack[1]->value, 1, 'Correct sack boolean';
            } else {
                is @data, 4, 'Extra data right size';
            }
            my @type = ${$data[$c++]->value}->value;
            my @quan = ${$data[$c++]->value}->value;
            is $type[0]->value, 34811;
            if ($client_ref eq 'FMS-234b') {
                is $type[1]->value, 2, 'Correct type';
                is $quan[0]->value, 34812;
                is $quan[1]->value, 9, 'Correct quantity ("Bags")';
            } else {
                is $type[1]->value, 1, 'Correct type';
                is $quan[0]->value, 34812;
                is $quan[1]->value, 1, 'Correct quantity';
            }
        } else {
            die "Bad event type provided";
        }

        # Check the USRN has been included
        if ($event_type =~ /^(935|943)/) {
            my @event_object = ${${$params[2]->value}->value->value}->value;
            is $event_object[0]->value, 'Source';
            my @object_ref = ${$event_object[1]->value}->value;
            is $object_ref[0]->value, 'Usrn';
            is $object_ref[1]->value, 'Street';
            my $usrn = ${$object_ref[2]->value}->value->value->value->value;

            my @data = ${$params[0]->value}->value->value;

            if ($event_type == 935) {
                is $usrn, '123/4567';
                is @data, 5, 'Name and source is only extra data';
            } elsif ($event_type == 943) {
                is $usrn, '123/4567';
                is @data, 4, 'Name (no surname) and source is only extra data';
            }
            my $c = 0;
            my @first_name = ${$data[$c++]->value}->value;
            is $first_name[0]->value, 1001;
            is $first_name[1]->value, 'Bob';
            if ($event_type == 935 ) {
                my @last = ${$data[$c++]->value}->value;
                is $last[0]->value, 1002;
                is $last[1]->value, 'Mould';
            }
            my @source = ${$data[$c++]->value}->value;
            is $source[0]->value, 1003;
            is $source[1]->value, 2;
            my @loc = ${$data[$c++]->value}->value;
            is $loc[0]->value, 1010;
            is $loc[1]->value, "Report title";
            my @notes = ${$data[$c++]->value}->value;
            is $notes[0]->value, 1008;
            is $notes[1]->value, 'Report details';
        }

        return SOAP::Result->new(result => {
            EventGuid => '1234',
        });
    } elsif ($args[0]->name eq 'GetEvent') {
        my $id = ${(${$args[3]->value}->value)[2]->value}->value->value;
        my $state_id = $id eq '1234-notcompleted' ? 4004 : 4002;
        return SOAP::Result->new(result => {
            EventTypeId => 935, # graffiti
            EventStateId => $state_id,
        });
    } elsif ($args[0]->name eq 'GetEventType') {
        my @params = ${$args[3]->value}->value;
        my $event_type = ${$params[2]->value}->value->value->value;
        if ( $event_type == 935 || $event_type == 943) {
            return SOAP::Result->new(result => {
                Workflow => { States => { State => [
                    { Id => 4001, Name => 'New', CoreState => 'New' },
                    { Id => 4002, Name => "Allocated to Crew", CoreState => 'Pending' },
                    { Id => 4003, Name => 'Completed', CoreState => 'Closed' },
                    { Id => 4004, Name => 'Not Completed', CoreState => 'Closed' },
                    { Id => 4005, Name => 'Rejected', CoreState => 'Cancelled' },
                ] } },
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1001, Name => "First Name" },
                    { Id => 1002, Name => "Surname" },
                    { Id => 1003, Name => "Source" },
                    { Id => 1010, Name => "Exact Location" },
                    { Id => 1008, Name => "Notes" },
                ] },
            });
        } elsif ($event_type == 1159) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1001, Name => "First Name" },
                    { Id => 1002, Name => "Surname" },
                    { Id => 1009, Name => "Payment Code" },
                    { Id => 21131, Name => "Bio Sacks" },
                    { Id => 34811, Name => "Paid Collection Container Type" },
                    { Id => 34812, Name => "Paid Collection Container Quantity" },
                    { Id => 34813, Name => "Container Type" },
                    { Id => 34814, Name => "Container Quantity" },
                ] },
            });
        } elsif ( $event_type == 2891) {
            return SOAP::Result->new(result => {
                Datatypes => { ExtensibleDatatype => [
                    { Id => 1001, Name => "Refuse BIN" },
                    { Id => 1002, Name => "Refuse BAG" },
                    { Id => 1003, Name => "Recycling BIN" },
                    { Id => 1004, Name => "Recycling BOX" },
                ] },
            });
        }
    } elsif ($args[0]->name eq 'PerformEventAction') {
        my @params = ${$args[3]->value}->value;
        my $actiontype_id = $params[0]->value;
        my @data = ${${$params[1]->value}->value->value}->value;
        my $datatype_id = $data[0]->value;
        my $description = $data[1]->value;
        if ($description =~ /Update on no further action/) {
            is $actiontype_id, 3;
            is $datatype_id, 1;
        } else {
            is $actiontype_id, 334;
            is $datatype_id, 112;
        }
        return SOAP::Result->new(result => { EventActionGuid => 'ABC' });
    } else {
        is $args[0], '';
    }
});

# Tests

use_ok('Open311::Endpoint::Integration::UK::Brent');
my $endpoint = Open311::Endpoint::Integration::UK::Brent->new;

subtest "GET Service List" => sub {
    my $res = $endpoint->run_test_request( GET => '/services.json' );
    ok $res->is_success, 'valid request'
        or diag $res->content;
    is_deeply decode_json($res->content),
        [ {
          "service_code" => "ATAK-PARK_FLY_TIPPING",
          "service_name" => "Parks fly-tipping",
          "description" => "Parks fly-tipping",
          "metadata" => "true",
          "group" => "Parks and open spaces",
          "keywords" => "",
          "type" => "realtime"
        }, {
          "service_code" => "ATAK-PARK_LITTERING",
          "service_name" => "Parks littering",
          "description" => "Parks littering",
          "metadata" => "true",
          "group" => "Parks and open spaces",
          "keywords" => "",
          "type" => "realtime"
        }, {
          "service_code" => "ATAK-PARK_LITTER_BIN_NEEDS_EMPTYING",
          "service_name" => "Park litter bin needs emptying",
          "description" => "Park litter bin needs emptying",
          "metadata" => "true",
          "group" => "Parks and open spaces",
          "keywords" => "",
          "type" => "realtime"
        }, {
          "service_code" => "Echo-1159",
          "service_name" => "Garden subscription",
          "description" => "Garden subscription",
          "metadata" => "true",
          "group" => "Waste",
          "keywords" => "waste_only",
          "type" => "realtime"
        }, {
            'type' => 'realtime',
            'service_code' => 'Echo-2891',
            'service_name' => 'Report missed collection',
            'group' => 'Waste',
            'description' => 'Report missed collection',
            'keywords' => 'waste_only',
            'metadata' => 'true'
        }, {
          "service_code" => "Echo-935",
          "service_name" => "Non-offensive graffiti",
          "description" => "Non-offensive graffiti",
          "metadata" => "true",
          "group" => "",
          "keywords" => "",
          "type" => "realtime"
        }, {
          "service_code" => "Echo-943",
          "service_name" => "Fly-posting",
          "description" => "Fly-posting",
          "metadata" => "true",
          "group" => "",
          "keywords" => "",
          "type" => "realtime"
        }, {
          "service_code" => "Symology-AbanVeh",
          "service_name" => "Abandoned vehicles",
          "description" => "Abandoned vehicles",
          "metadata" => "true",
          "group" => "",
          "keywords" => "",
          "type" => "realtime"
       } ], 'correct json returned';
};

subtest "POST service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Symology-AbanVeh',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[NSGRef]' => NSGREF,
        'attribute[burnt]' => 'No',
        'attribute[car_details]' => 'Details',
        'attribute[easting]' => EASTING,
        'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => 123,
        'attribute[title]' => 'Report title'
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "Symology-1001"
        } ], 'correct json returned';
};

subtest "POST Echo service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Echo-935',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[usrn]' => NSGREF,
        #'attribute[easting]' => EASTING,
        #'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => 234,
        'attribute[title]' => 'Report title',
        'attribute[description]' => 'Report details',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "Echo-1234"
        } ], 'correct json returned';
};

subtest "POST other Echo service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Echo-943',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[usrn]' => NSGREF,
        'attribute[fixmystreet_id]' => 234,
        'attribute[title]' => 'Report title',
        'attribute[description]' => 'Report details',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "Echo-1234"
        } ], 'correct json returned';
};

subtest "POST missed collection Echo service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Echo-2891',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "Report missed collection",
        lat => 51,
        long => -1,
        'attribute[fixmystreet_id]' => 234,
        'attribute[service_id]' => 262,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "Echo-1234"
        } ], 'correct json returned';
};

subtest "POST missed recycling collection Echo service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Echo-2891',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "Report missed collection",
        lat => 51,
        long => -1,
        'attribute[fixmystreet_id]' => 235,
        'attribute[service_id]' => 265,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "Echo-1234"
        } ], 'correct json returned';
};

subtest "POST waste Echo service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Echo-1159',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "Garden subscription details",
        lat => 51,
        long => -1,
        'attribute[usrn]' => NSGREF,
        'attribute[fixmystreet_id]' => 234,
        'attribute[title]' => 'Garden subscription - New',
        'attribute[description]' => 'Garden subscription details',
        'attribute[service_id]' => 317,
        'attribute[PaymentCode]' => 'PAY12345',
        'attribute[Paid_Collection_Container_Quantity]' => 1,
        'attribute[Paid_Collection_Container_Type]' => 1,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "Echo-1234"
        } ], 'correct json returned';
};

subtest "POST sack waste Echo service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Echo-1159',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "Garden subscription details",
        lat => 51,
        long => -1,
        'attribute[usrn]' => NSGREF,
        'attribute[fixmystreet_id]' => '234b',
        'attribute[title]' => 'Garden subscription - New',
        'attribute[description]' => 'Garden subscription details',
        'attribute[service_id]' => 317,
        'attribute[PaymentCode]' => 'PAY12345',
        'attribute[Paid_Collection_Container_Quantity]' => 1,
        'attribute[Paid_Collection_Container_Type]' => 2,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "Echo-1234"
        } ], 'correct json returned';
};

subtest "POST Parks littering ATAK service request OK" => sub {
    set_fixed_time('2023-07-27T12:00:00Z');
    my $mock_ua = Test::MockModule->new('LWP::UserAgent');
    $mock_ua->mock('get', sub {
        my ($self, $url) = @_;
        if ($url eq 'http://example.org/photo/1.jpeg') {
            my $image_data = path(__FILE__)->sibling('files')->child('test_image.jpg')->slurp;
            my $response = HTTP::Response->new(200, 'OK', []);
            $response->header('Content-Disposition' => 'attachment; filename="1.jpeg"');
            $response->header('Content-Type' => 'image/jpeg');
            $response->content($image_data);
            return $response;
        } else {
            return HTTP::Response->new(404, 'Not Found', [], '');
        }
    });

    $mock_ua->mock('post', sub {
        my ($self, $url, %headers) = @_;
        if ($url eq 'https://example.com/ords/hws/atak/v1/enq') {
            is $headers{Authorization}, 'AUTH-123';

            my $data = decode_json($headers{Content})->{tasks}->[0];
            is $data->{issue}, "Category: Parks littering\nGroup: Parks and open spaces\nLocation: Location name\n\n" .
                "location of problem: title\n\ndetail: detail\n\nurl: url\n\n" .
                "Submitted via FixMyStreet\n";
            is $data->{client_ref}, '42';
            is $data->{project_name}, 'LB BRENT';
            is $data->{project_code}, 'C123';
            is $data->{taken_on}, '2023-07-27T12:00:00Z';
            is $data->{location_name}, 'Location name';
            is $data->{caller}, '';
            is $data->{resolve_by}, '';
            is $data->{location}->{type}, 'Point';
            is_deeply $data->{location}->{coordinates}, [ -1, 51 ];
            my $photo = $data->{attachments}->[0];
            is $photo->{filename}, '1.jpeg';
            is $photo->{description}, 'Image 1';
            like $photo->{data}, qr{^data:image/jpeg;base64,/9j/4};

            return HTTP::Response->new(200, 'OK', [], '{"Processed task 1": "123ABC"}');
        } elsif ($url eq 'https://example.com/ords/hws/atak/v1/login') {
            return HTTP::Response->new(200, 'OK', [], '{"token": "AUTH-123"}');
        } else {
            return HTTP::Response->new(404, 'Not Found', [], '');
        }
    });

    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'ATAK-PARK_LITTERING',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "Lots of litter in the park",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[location_name]' => 'Location name',
        'attribute[easting]' => EASTING,
        'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => 42,
        'attribute[report_url]' => 'url',
        'attribute[detail]' => 'detail',
        'attribute[title]' => 'title',
        'attribute[group]' => 'Parks and open spaces',
    );
    ok $res->is_success, 'valid request';

    is_deeply decode_json($res->content), [
        {
            "service_request_id" => "ATAK-123ABC"
        }
    ], 'correct json returned' or diag $res->content;
};

subtest "POST Echo update OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'test',
        updated_datetime => '2019-03-01T12:00:00Z',
        service_code => 'Echo-935',
        service_request_id => "Echo-1234-allocated",
        status => 'OPEN',
        description => "This is the update",
        update_id => 456,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            'update_id' => "Echo-ABC",
        } ], 'correct json returned';
};

subtest "POST Echo update on closed report OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'test',
        updated_datetime => '2019-03-01T12:00:00Z',
        service_code => 'Echo-935',
        service_request_id => "Echo-1234-notcompleted",
        status => 'NO_FURTHER_ACTION',
        description => "Update on no further action",
        update_id => 456,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            'update_id' => "Echo-ABC",
        } ], 'correct json returned';
};

subtest "POST update OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        #jurisdiction_id => 'brent',
        api_key => 'test',
        updated_datetime => '2019-03-01T12:00:00Z',
        service_code => 'Symology-AbanVeh',
        service_request_id => "Symology-1001",
        status => 'OPEN',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the update",
        service_request_id_ext => 5678,
        update_id => 456,
        media_url => 'http://example.org/photo/1.jpeg',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            'update_id' => "Symology-456",
        } ], 'correct json returned';
};

sub _get_and_check_service_request_updates {
    my ($start_date, $end_date, $expected) = @_;
    my $res = $endpoint->run_test_request(
        GET => sprintf(
            '/servicerequestupdates.json?start_date=%s&end_date=%s',
            $start_date,
            $end_date
        )
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    my $response = decode_json($res->content);
    is_deeply $response, $expected, 'correct json returned';
}

subtest "GET updates OK" => sub {
    _get_and_check_service_request_updates(
        '2018-11-27T00:00:00Z',
        '2018-11-29T00:00:00Z',
        [
            {
                description => "",
                media_url => '',
                service_request_id => 'Symology-323',
                status => 'investigating',
                update_id => 'Symology-00000323_6',
                updated_datetime => '2018-11-28T15:05:00+00:00',
                external_status_code => '19',
            },
            {
                description => "Text going here explaining reason for no further action",
                media_url => '',
                service_request_id => 'Symology-323',
                status => 'no_further_action',
                update_id => 'Symology-00000323_8',
                updated_datetime => '2018-11-28T15:05:00+00:00',
                external_status_code => '21_NFA',
            }
        ]
    );
};

subtest "GET ATAK service request updates OK" => sub {
    my $mock_ua = Test::MockModule->new('LWP::UserAgent');

    # Handle logins.
    $mock_ua->mock('post', sub {
        my ($self, $url) = @_;
        if ($url eq 'https://example.com/ords/hws/atak/v1/login') {
            return HTTP::Response->new(200, 'OK', [], '{"token": "AUTH-123"}');
        }
        return HTTP::Response->new(404, 'Not Found', [], '');
    });

    set_fixed_time('2023-08-02T00:00:00Z');
    $atak_endpoint->init_update_gathering_files(DateTime->now->subtract(days => 1));

    $mock_ua->mock('get', sub {
        my ($self, $url) = @_;
        like $url, qr/from=2023-08-01T00:00:00Z/, "correct from time";
        like $url, qr/to=2023-08-02T00:00:00Z/, "correct to time";
        return HTTP::Response->new(200, 'OK', [], '{
            "tasks": [
                {
                    "testing_comment": "missing client_ref",
                    "task_comments": "Closed - Completed",
                    "task_d_created": "2023-08-01T00:00:00Z",
                    "task_d_planned": "2023-08-01T00:00:00Z",
                    "task_d_completed": "2023-08-01T00:00:00Z",
                    "task_d_approved": "2023-08-01T00:00:00Z",
                    "task_p_id": "123"
                },
                {
                    "client_ref": "missing created time",
                    "task_comments": "Closed - Completed",
                    "task_d_planned": "2023-08-01T00:00:00Z",
                    "task_d_completed": "2023-08-01T00:00:00Z",
                    "task_d_approved": "2023-08-01T00:00:00Z",
                    "task_p_id": "124"
                },
                {
                    "client_ref": "unknown state",
                    "task_comments": "Closed - Unknown",
                    "task_d_created": "2023-08-01T00:00:00Z",
                    "task_d_planned": "2023-08-01T00:00:00Z",
                    "task_d_completed": "2023-08-01T00:00:00Z",
                    "task_d_approved": "2023-08-01T00:00:00Z",
                    "task_p_id": "125"
                },
                {
                    "client_ref": "issue too old",
                    "task_comments": "Closed - Completed",
                    "task_d_created": "2022-08-01T00:00:00Z",
                    "task_d_planned": "2023-08-01T00:00:00Z",
                    "task_d_completed": "2023-08-01T00:00:00Z",
                    "task_d_approved": "2023-08-01T00:00:00Z",
                    "task_p_id": "126"
                },
                {
                    "client_ref": "test",
                    "task_comments": "Closed - Passed to Brent",
                    "task_d_created": "2023-08-01T00:00:00Z",
                    "task_d_planned": "2023-08-01T01:00:00Z",
                    "task_d_completed": "2023-08-01T02:00:00Z",
                    "task_d_approved": "2023-08-01T03:00:00Z",
                    "task_p_id": "127"
                }
            ]
        }');
    });

    $atak_endpoint->gather_updates();

    _get_and_check_service_request_updates(
        '2023-08-01T00:00:00Z',
        '2023-08-02T00:00:00Z',
        [
            {
                description => '',
                media_url => '',
                service_request_id => 'ATAK-127',
                status => 'internal_referral',
                update_id => 'ATAK-test_1690858800',
                updated_datetime => '2023-08-01T03:00:00Z',
                external_status_code => 'Closed - Passed to Brent',
            },
        ]
    );

    # Next day.
    set_fixed_time('2023-08-03T00:00:00Z');

    $mock_ua->mock('get', sub {
        my ($self, $url) = @_;
        like $url, qr/from=2023-08-01T03:00:00Z/, "correct from time";
        like $url, qr/to=2023-08-03T00:00:00Z/, "correct to time";
        # One of the times is outside of query window, next query should start from range end
        # rather than the 'future' time.
        return HTTP::Response->new(200, 'OK', [], '{
            "tasks": [
                {
                    "testing_comment": "new update but same ATAK status - should ignore",
                    "client_ref": "test",
                    "task_comments": "Closed - Passed to Brent",
                    "task_d_created": "2023-08-01T00:00:00Z",
                    "task_d_planned": "2023-08-02T01:00:00Z",
                    "task_d_completed": "2023-08-02T02:00:00Z",
                    "task_d_approved": "2023-08-04T03:00:00Z",
                    "task_p_id": "128"
                }
            ]
        }');
    });

    $atak_endpoint->gather_updates();

    # We get the old update and nothing new.
    _get_and_check_service_request_updates(
        '2023-08-01T00:00:00Z',
        '2023-08-03T00:00:00Z',
        [
            {
                description => "",
                media_url => '',
                service_request_id => 'ATAK-127',
                status => 'internal_referral',
                update_id => 'ATAK-test_1690858800',
                updated_datetime => '2023-08-01T03:00:00Z',
                external_status_code => 'Closed - Passed to Brent',
            },
        ]
    );

    # Next day.
    set_fixed_time('2023-08-04T00:00:00Z');

    $mock_ua->mock('get', sub {
        my ($self, $url) = @_;
        like $url, qr/from=2023-08-03T00:00:00Z/, "correct from time";
        like $url, qr/to=2023-08-04T00:00:00Z/, "correct to time";
        return HTTP::Response->new(200, 'OK', [], '{
            "tasks": [
                {
                    "testing_comment": "new ATAK status - should get an update",
                    "client_ref": "test",
                    "task_comments": "Closed - Completed description",
                    "task_d_created": "2023-08-01T00:00:00Z",
                    "task_d_planned": "2023-08-03T01:00:00Z",
                    "task_d_completed": "2023-08-03T02:00:00Z",
                    "task_d_approved": "2023-08-03T03:00:00Z",
                    "task_p_id": "129"
                }
            ]
        }');
    });

    $atak_endpoint->gather_updates();

    _get_and_check_service_request_updates(
        '2023-08-02T00:00:00Z',
        '2023-08-04T00:00:00Z',
        [
            {
                description => "description",
                media_url => '',
                service_request_id => 'ATAK-129',
                status => 'fixed',
                update_id => 'ATAK-test_1691031600',
                updated_datetime => '2023-08-03T03:00:00Z',
                external_status_code => 'Closed - Completed',
            },
        ]
    );

    # A year later.
    set_fixed_time('2024-08-05T00:00:00Z');

    $mock_ua->mock('get', sub {
        my ($self, $url) = @_;
        like $url, qr/from=2023-08-03T03:00:00Z/, "correct from time";
        like $url, qr/to=2024-08-05T00:00:00Z/, "correct to time";
        return HTTP::Response->new(200, 'OK', [], '{}');
    });

    $atak_endpoint->gather_updates();

    # Old updates should be gone.
    _get_and_check_service_request_updates(
        '2023-08-01T00:00:00Z',
        '2024-08-05T00:00:00Z',
        []
    );
};

subtest "ATAK issue text formatting" => sub {

    dies_ok { $atak_endpoint->_format_issue_text(
        133, 'category', 'group', 'location name', 'url', 'title', 'detail'
    ) } "formatting issue text fails when inputs are too big";

    my $issue_text =  $atak_endpoint->_format_issue_text(
        134, 'category', 'group', 'location name', 'url', 'title', 'detail'
    );
    is $issue_text, "Category: category\nGroup: group\nLocation: location name\n\nlocation of problem: title\n\n" .
        "detail: ...\n\nurl: url\n\nSubmitted via FixMyStreet\n";

    $issue_text =  $atak_endpoint->_format_issue_text(
        135, 'category', 'group', 'location name', 'url', 'title', 'detail'
    );
    is $issue_text, "Category: category\nGroup: group\nLocation: location name\n\nlocation of problem: title\n\n" .
        "detail: d...\n\nurl: url\n\nSubmitted via FixMyStreet\n";

    $issue_text =  $atak_endpoint->_format_issue_text(
        139, 'category', 'group', 'location name', 'url', 'title', 'detail'
    );
    is $issue_text, "Category: category\nGroup: group\nLocation: location name\n\nlocation of problem: title\n\n" .
        "detail: detail\n\nurl: url\n\nSubmitted via FixMyStreet\n";
};

done_testing;

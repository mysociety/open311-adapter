use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use Test::More;
use Test::MockModule;

use JSON::MaybeXS;
use Path::Tiny;

use constant {
    REPORT_NSGREF => 0,
    REPORT_DATE => 1,
    REPORT_TIME => 2,
    REPORT_USER => 3,
    REPORT_REQUEST_TYPE => 4,
    REPORT_PRIORITY => 5,
    REPORT_AC1 => 6,
    REPORT_ACT2 => 7,
    REPORT_REF => 8,
    REPORT_DESC => 9,
    REPORT_EASTING => 10,
    REPORT_NORTHING => 11,
    REPORT_INWEB => 12,
    REPORT_SERVICECODE => 13,
    REPORT_NEXTACTION => 14,
    REPORT_NEXTINSPECTION => 15,
    REPORT_NEXTACTIONUSERNAME => 16,
    UPDATE_REPORT_ID => 123,
};

use constant {
    NSGREF => '123/4567',
};

use constant {
    NORTHING => 100,
    EASTING => 100,
    EASTING_AREAA => 101,
    EASTING_AREAB => 102,
    EASTING_BAD => 103,
};

my $soap_lite = Test::MockModule->new('SOAP::Lite');
$soap_lite->mock(call => sub {
    # This is called when a test below makes a SOAP call, along with the data
    # to be passed via SOAP to the server. We check the values here, then pass
    # back a mocked result.
    my ($cls, @args) = @_;
    if ($args[0] eq 'SendRequestAdditionalGroup') {
        my @request = ${$args[2]->value}->value;
        is $request[REPORT_NSGREF]->value, NSGREF;
        is $request[REPORT_NEXTACTION]->value, undef;
        is $request[REPORT_NORTHING]->value, NORTHING;
        my $photo_desc = "\n\n[ This report contains a photo, see: http://example.org/photo/1.jpeg ]";
        is $request[REPORT_DESC]->value, "This is the details$photo_desc";
        is $request[REPORT_PRIORITY]->value, ($request[REPORT_REQUEST_TYPE]->value eq "Bridges" ? 'Priority1' : 'Priority2');
        if ( $request[REPORT_REQUEST_TYPE]->value eq "Potholes" ) {
            is $request[REPORT_NEXTACTIONUSERNAME]->value, 'POT00001';
        } elsif ( $request[REPORT_EASTING]->value == EASTING_AREAA ) {
            is $request[REPORT_NEXTACTIONUSERNAME]->value, 'USER0001';
        } elsif ( $request[REPORT_EASTING]->value == EASTING_AREAB ) {
            is $request[REPORT_NEXTACTIONUSERNAME]->value, 'USER0002';
        } elsif ( $request[REPORT_EASTING]->value == EASTING_BAD ) {
            is $request[REPORT_NEXTACTIONUSERNAME]->value, '';
            return {
                StatusCode => 1,
                StatusMessage => 'Failed',
                SendRequestResults => {
                    SendRequestResultRow => {
                        RecordType => 1,
                        MessageText => 'Username required for notification',
                    }
                }
            };
        }
        return {
            StatusCode => 0,
            StatusMessage => 'Success',
            SendRequestResults => {
                SendRequestResultRow => {
                    RecordType => 2,
                    ConvertCRNo => $request[REPORT_REQUEST_TYPE]->value eq "Bridges" ? 1001 : 1002,
                }
            }
        };
    } elsif ($args[0] eq 'SendEventAction') {
        my @request = map { $_->value } ${$args[2]->value}->value;
        my $photo_desc = "\n\n[ This update contains a photo, see: http://example.org/photo/1.jpeg ]";
        my $report_id = $request[2];
        my $code = 'GN11';
        is_deeply \@request, [ 'ServiceCode', 1001, $report_id, $code, '', 'FMS', "This is the update$photo_desc" ];
        return {
            StatusCode => 0,
            StatusMessage => 'Event Loaded',
            SendEventActionResults => {
                SendEventActionResultRow => {
                    RecordType => 2,
                }
            }
        };
    } else {
        is $args[0], '';
    }
});

my $centralbeds_integ = Test::MockModule->new('Integrations::Symology');
$centralbeds_integ->mock(config => sub {
    {
        endpoint_url => 'http://www.example.org/',
    }
});

my $centralbeds_end = Test::MockModule->new('Open311::Endpoint::Integration::UK::CentralBedfordshire');
$centralbeds_end->mock(endpoint_config => sub {
    {
        username => 'FMS',
        nsgref_to_action => {},
        customer_defaults => {
            CustomerType => "",
            ContactType => "",
        },
        area_to_username => {
            AreaA => "USER0001",
            AreaB => "USER0002",
            AreaC => "USER0003",
        },
        category_mapping => {
            Bridges => {
                name => 'Bridges',
                parameters => {
                    ServiceCode => 'ServiceCode',
                    RequestType => 'Bridges',
                    Priority => 'Priority1',
                },
                questions => [],
                logic => [],
            },
            Potholes => {
                name => 'Potholes',
                parameters => {
                    ServiceCode => 'ServiceCode',
                    RequestType => 'Potholes',
                    Priority => 'Priority2',
                    NextActionUserName => 'POT00001',
                },
                questions => [],
                logic => [],
            },
        },
        stage_mapping => {
            RECORDED => 'open',
            CLEARED => 'closed',
        },
        updates_sftp => {
            out => path(__FILE__)->sibling('files/centralbedfordshire/updates')->stringify,
        },
    }
});

use Open311::Endpoint::Integration::UK::CentralBedfordshire;

my $endpoint = Open311::Endpoint::Integration::UK::CentralBedfordshire->new;

subtest "GET services" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    my $content = decode_json($res->content);
    my $services = [ sort { $a->{service_code} cmp $b->{service_code} } @$content ];
    is_deeply $services,
        [
            {
                "service_code" => "Bridges",
                "service_name" => "Bridges",
                "description" => "Bridges",
                "metadata" => "true",
                "group" => "",
                "keywords" => "",
                "type" => "realtime"
            },
            {
                "service_code" => "Potholes",
                "service_name" => "Potholes",
                "description" => "Potholes",
                "metadata" => "true",
                "group" => "",
                "keywords" => "",
                "type" => "realtime"
            },
        ], 'correct json returned';
};

subtest "GET service" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services/Bridges.json',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), {
        "service_code" => "Bridges",
            "attributes" => [
                {
                   "datatype" => "number",
                   "code" => "easting",
                   "order" => 1,
                   "required" => "true",
                   "automated" => "server_set",
                   "description" => "easting",
                   "variable" => "false",
                   "datatype_description" => ""
                },
                {
                   "datatype" => "number",
                   "code" => "northing",
                   "order" => 2,
                   "required" => "true",
                   "automated" => "server_set",
                   "description" => "northing",
                   "datatype_description" => "",
                   "variable" => "false"
                },
                {
                   "datatype_description" => "",
                   "variable" => "false",
                   "description" => "external system ID",
                   "automated" => "server_set",
                   "required" => "true",
                   "order" => 3,
                   "code" => "fixmystreet_id",
                   "datatype" => "string"
                },
                {
                   "description" => "Unit ID",
                   "variable" => "true",
                   "datatype_description" => "",
                   "automated" => "hidden_field",
                   "order" => 4,
                   "required" => "false",
                   "datatype" => "string",
                   "code" => "UnitID"
                },
                {
                   "description" => "NSG reference",
                   "variable" => "true",
                   "datatype_description" => "",
                   "automated" => "hidden_field",
                   "order" => 5,
                   "required" => "false",
                   "datatype" => "string",
                   "code" => "NSGRef"
                },
                {
                   "required" => "false",
                   "order" => 6,
                   "datatype" => "string",
                   "code" => "contributed_by",
                   "description" => "Contributed by",
                   "variable" => "true",
                   "datatype_description" => "",
                   "automated" => "server_set"
                },
                {
                   "required" => "false",
                   "order" => 7,
                   "datatype" => "string",
                   "code" => "area_code",
                   "description" => "Area code",
                   "variable" => "true",
                   "datatype_description" => "",
                   "automated" => "server_set"
                },
            ],
        }, 'correct json returned';
};

subtest "POST Bridges Area A OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Bridges',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[NSGRef]' => NSGREF,
        'attribute[easting]' => EASTING_AREAA,
        'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => UPDATE_REPORT_ID,
        'attribute[area_code]' => 'AreaA',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 1001
        } ], 'correct json returned';
};

subtest "POST Bridges Area B OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Bridges',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[NSGRef]' => NSGREF,
        'attribute[easting]' => EASTING_AREAB,
        'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => UPDATE_REPORT_ID,
        'attribute[area_code]' => 'AreaB',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 1001
        } ], 'correct json returned';
};

subtest "POST Bridges with no area fails" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Bridges',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[NSGRef]' => NSGREF,
        'attribute[easting]' => EASTING_BAD,
        'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => UPDATE_REPORT_ID,
    );
    ok !$res->is_success, 'invalid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "description" => "Couldn't create SendRequest in Symology: Failed - Username required for notification\n",
            "code" => 500,
        } ], 'correct json returned';
};

subtest "POST Potholes OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'Potholes',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        media_url => 'http://example.org/photo/1.jpeg',
        'attribute[NSGRef]' => NSGREF,
        'attribute[easting]' => EASTING,
        'attribute[northing]' => NORTHING,
        'attribute[fixmystreet_id]' => 456,
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 1002
        } ], 'correct json returned';
};

subtest "POST update OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        api_key => 'test',
        updated_datetime => '2019-03-01T12:00:00Z',
        service_code => 'Bridges',
        service_request_id => 1001,
        status => 'OPEN',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the update",
        service_request_id_ext => UPDATE_REPORT_ID,
        update_id => 789,
        media_url => 'http://example.org/photo/1.jpeg',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            'update_id' => 789,
        } ], 'correct json returned';
};

subtest "GET updates OK" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.json?start_date=2020-11-01T00:08:00Z&end_date=2020-11-01T10:00:00Z',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    my $response = decode_json($res->content);
    is_deeply $response,
        [
            {
                description => '',
                media_url => '',
                service_request_id => 789951,
                status => 'open',
                update_id => '789951_1cd1d8d5',
                updated_datetime => '2020-11-01T08:05:00+00:00',
            },
            {
                description => '',
                media_url => '',
                service_request_id => 789952,
                status => 'open',
                update_id => '789952_14f97f3a',
                updated_datetime => '2020-11-01T08:56:00+00:00',
            },
            {
                description => '',
                media_url => '',
                service_request_id => 789953,
                status => 'open',
                update_id => '789953_b0446ae3',
                updated_datetime => '2020-11-01T09:35:00+00:00',
            },
            {
                description => 'This has now been resolved.',
                media_url => '',
                service_request_id => 789951,
                status => 'closed',
                update_id => '789951_b287d6e6',
                updated_datetime => '2020-11-01T09:59:00+00:00',
            }
        ], 'correct json returned';
};

done_testing;

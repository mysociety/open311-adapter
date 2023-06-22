package main;

use strict;
use warnings;

use JSON::MaybeXS;
use Test::MockModule;
use Test::More;
use Moo;
use Open311::Endpoint::Integration::UK::CentralBedfordshire::Jadu;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }

my @sent_payloads;

my $integration = Test::MockModule->new('Integrations::Jadu');

$integration->mock('create_case_and_get_reference', sub {
    my ($self, undef, $payload) = @_;
    push @sent_payloads, $payload;
    return "test_case_reference";
});

$integration->mock('get_case_summaries_by_filter', sub {
    my ($self, undef, undef, $page_number) = @_;
    if ($page_number == 1) {
        return {
            num_items => 3,
            items => [
                {   # Too recent; shouldn't be included.
                    reference => "case_1",
                    updated_at => "2023-07-05T00:00:00+0000",
                    status => {
                        title => 'Closed'
                    },
                },
                {   # Unkown status; shouldn't be included.
                    reference => "case_2",
                    updated_at => "2023-07-03T12:00:00+0000",
                    status => {
                        title => 'Unknown'
                    },
                },
                {   # Should be included.
                    reference => "case_3",
                    updated_at => "2023-07-03T12:00:00+0000",
                    status => {
                        title => 'Closed'
                    },
                }
            ]
        };
    } elsif ($page_number == 2) {
        return {
            num_items => 1,
            items => [
                {   # Too old, shouldn't be included and querying should stop.
                    reference => "case_4",
                    updated_at => "2023-07-02T12:00:00+0000",
                    status => {
                        title => 'Closed'
                    },
                },
            ]
        }
    }
    die "unexpected page number: " . $page_number;
});

my $centralbedfordshire_jadu = Test::MockModule->new('Open311::Endpoint::Integration::UK::CentralBedfordshire::Jadu');
$centralbedfordshire_jadu->mock('_build_config_file', sub {
    path(__FILE__)->sibling('centralbedfordshire_jadu.yml');
});


my $endpoint = Open311::Endpoint::Integration::UK::CentralBedfordshire::Jadu->new;

subtest "POST service request" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'centralbedfordshire_jadu',
        api_key => 'test',
        service_code => 'fly-tipping',
        first_name => 'John',
        last_name => 'Smith',
        email => 'john.smith@example.com',
        lat => 52.035536,
        long => -0.360673,
        phone => '07700900077',
        'attribute[easting]' => 12548,
        'attribute[northing]' => 238727,
        'attribute[fixmystreet_id]' => 1,
        'attribute[report_url]' => 'http://fixmystreet.com/reports/1',
        'attribute[location_description]' => 'Near the junction.',
        'attribute[land_type]' => 'Footpath',
        'attribute[type_of_waste]' => 'Asbestos',
        'attribute[type_of_waste]' => 'Black bags',
        'attribute[description_of_waste]' => 'Black bags of asbestos.',
        'attribute[fly_tip_witnessed]' => 'Yes',
        'attribute[fly_tip_date_and_time]' => '14:30:36Z',
        'attribute[description_of_alleged_offender]' => 'Stealthy.',
        'attribute[usrn]' => '25202550',
        'attribute[street]' => "Monk's Walk",
        'attribute[town]' => "Chicksands",
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    my $sent_payload = pop @sent_payloads;

    my $expected_payload = {
        'sys-channel' => 'test_sys_channel',
        'ens-latitude' => '52.035536',
        'ens-longitude' => '-0.360673',
        'coordinates' => '52.035536,-0.360673',
        'usrn' => '25202550',
        'sys-town' => 'Chicksands',
        'eso-officer' => 'area_5',
        'ens-street' => "Monk's Walk",
        'sys-first-name' => 'John',
        'sys-last-name' => 'Smith',
        'sys-email-address' => 'john.smith@example.com',
        'sys-telephone-number' => '07700900077',
        'ens-google-street-view-url' => 'https://google.com/maps/@?api=1&map_action=pano&viewpoint=52.035536,-0.360673',
        'ens-location_description' => 'Near the junction.',
        'ens-land-type' => 'Footpath',
        'ens-type-of-waste-fly-tipped' => 'Asbestos,Black bags',
        'ens-description-of-fly-tipped-waste' => 'Black bags of asbestos.',
        'ens-fly-tip-date' => '2023-07-03',
        'ens-fly-tip-time' => '14:30',
        'ens-description-of-alleged-offender' => 'Stealthy.',
        'fms-reference' => 'http://fixmystreet.com/reports/1',
        'ens-fly-tip-witnessed' => 'Yes',
    };
    is_deeply $sent_payload, $expected_payload;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "test_case_reference"
        } ], 'correct json returned';
};

subtest "GET service request updates" => sub {
    my $start_date = '2023-07-03T00:00:00Z';
    my $end_date = '2023-07-04T00:00:00Z';

    my $res = $endpoint->run_test_request(
        GET => sprintf('/servicerequestupdates.json?start_date=%s&end_date=%s', $start_date, $end_date),
        jurisdiction_id => 'centralbedfordshire_jadu',
        api_key => 'test',
        service_code => 'fly-tipping',
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), [
        {
            status => "closed",
            update_id => "case_3_1688385600",
            media_url => "",
            description => "",
            service_request_id => "case_3",
            updated_datetime => "2023-07-03T12:00:00Z",
            external_status_code => "Closed"
        }
    ];
};

done_testing;

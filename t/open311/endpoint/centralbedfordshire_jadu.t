use strict;
use warnings;

use Test::MockFile qw< nostrict >;
use Test::MockModule;
use Test::MockTime qw( :all );

use DateTime;
use File::Temp qw(tempfile);
use JSON::MaybeXS;
use Test::More;
use Moo;
use Open311::Endpoint::Integration::UK::CentralBedfordshire::Jadu;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }

my (undef, $status_tracking_file) = tempfile(EXLOCK => 0);
my (undef, $update_storage_file) = tempfile(EXLOCK => 0);

my $config_string = '
    sys_channel: "test_sys_channel"
    case_status_to_fms_status:
        "Action Scheduled 1": "action_scheduled"
        "Action Scheduled 2": "action_scheduled"
        "Investigating": "investigating"
    case_status_to_fms_status_timed:
        "Closed":
            fms_status: "closed"
            days_to_wait: 1
    case_status_tracking_file: "%s"
    case_status_tracking_max_age_days: 365
    update_storage_file: "%s"
    update_storage_max_age_days: 365
    town_to_officer:
        "chicksands": "area_1"';

my $config = Test::MockFile->file( "/config.yml", sprintf($config_string, $status_tracking_file, $update_storage_file));

my $integration = Test::MockModule->new('Integrations::Jadu');
my $geocode = Test::MockModule->new('Geocode::SinglePoint');

my $centralbedfordshire_jadu = Test::MockModule->new('Open311::Endpoint::Integration::UK::CentralBedfordshire::Jadu');
$centralbedfordshire_jadu->mock('_build_config_file', sub { '/config.yml' });

my $endpoint = Open311::Endpoint::Integration::UK::CentralBedfordshire::Jadu->new;

subtest "POST service request" => sub {
    my @sent_payloads;
    $integration->mock('create_case_and_get_reference', sub {
        my ($self, undef, $payload) = @_;
        push @sent_payloads, $payload;
        return "test_case_reference";
    });

    $geocode->mock('get_nearest_addresses', sub {
        return [
            {
                USRN => 25202550,
                STREET => "Monk's Walk",
                TOWN => "Chicksands",
            }
        ]
    });

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
        'attribute[title]' => 'Near the junction.',
        'attribute[description]' => 'Black bags of asbestos.',
        'attribute[easting]' => 12548,
        'attribute[northing]' => 238727,
        'attribute[fixmystreet_id]' => 1,
        'attribute[report_url]' => 'http://fixmystreet.com/reports/1',
        'attribute[land_type]' => 'Footpath',
        'attribute[type_of_waste]' => 'Asbestos',
        'attribute[type_of_waste]' => 'Black bags',
        'attribute[fly_tip_witnessed]' => 'Yes',
        'attribute[fly_tip_date_and_time]' => '2023-07-03T14:30:36Z',
        'attribute[description_of_alleged_offender]' => 'Stealthy.',
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
        'eso-officer' => 'area_1',
        'ens-street' => "Monk's Walk",
        'sys-first-name' => 'John',
        'sys-last-name' => 'Smith',
        'sys-email-address' => 'john.smith@example.com',
        'sys-telephone-number' => '07700900077',
        'ens-google-street-view-url' => 'https://google.com/maps/@?api=1&map_action=pano&viewpoint=52.035536,-0.360673',
        'ens-location-description' => 'Near the junction.',
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
        } ], 'correct response returned';
};

subtest "GET service request updates" => sub {
    set_fixed_time('2023-01-31T00:00:00Z');

    my $start_from = DateTime->now()->subtract(days => 1);
    $endpoint->init_update_gathering_files($start_from);

    $integration->mock('get_case_summaries_by_filter', sub {
        my ($self, undef, undef, $page_number) = @_;
        if ($page_number == 1) {
            return {
                num_items => 3,
                items => [
                    {   # Should only result in a closed update after a day.
                        reference => "case_1",
                        updated_at => "2023-01-31T00:00:00+0000",
                        created_at => "2023-01-30T16:00:00+0000",
                        status => {
                            title => 'Closed'
                        },
                    },
                    {   # Shouldn't result in an update as already in action_scheduled.
                        reference => "case_1",
                        updated_at => "2023-01-30T18:00:00+0000",
                        created_at => "2023-01-30T16:00:00+0000",
                        status => {
                            title => 'Action Scheduled 2'
                        },
                    },
                    {   # Should result in an action_scheduled update.
                        reference => "case_1",
                        updated_at => "2023-01-30T17:00:00+0000",
                        created_at => "2023-01-30T16:00:00+0000",
                        status => {
                            title => 'Action Scheduled 1'
                        },
                    },
                    {   # Should result in an investigating update.
                        reference => "case_1",
                        updated_at => "2023-01-30T16:00:00+0000",
                        created_at => "2023-01-30T16:00:00+0000",
                        status => {
                            title => 'Investigating'
                        },
                    },
                    {   # Shouldn't result in an update - unmapped case status.
                        reference => "case_unmapped_status",
                        updated_at => "2023-01-30T15:00:00+0000",
                        created_at => "2023-01-30T00:00:00+0000",
                        status => {
                            title => 'Unmapped'
                        },
                    },
                    {   # Shouldn't result in an update - case too old.
                        reference => "case_too_old",
                        updated_at => "2023-01-30T14:00:00+0000",
                        created_at => "2022-01-30T00:00:00+0000",
                        status => {
                            title => 'Open'
                        },
                    }
                ]
            };
        } elsif ($page_number == 2) {
            return {
                num_items => 1,
                items => [
                    {   # Update too old, should stop querying.
                        reference => "case_update_too_old",
                        updated_at => "2023-01-29T23:59:59+0000",
                        status => {
                            title => 'Closed'
                        },
                    },
                ]
            }
        }
        die "unexpected page number: " . $page_number;
    });

    $endpoint->gather_updates();

    my $start_date = '2023-01-01T00:00:00Z';
    my $end_date = '2023-02-28T00:00:00Z';

    my $res = $endpoint->run_test_request(
        GET => sprintf('/servicerequestupdates.json?start_date=%s&end_date=%s', $start_date, $end_date),
        jurisdiction_id => 'centralbedfordshire_jadu',
        api_key => 'test',
        service_code => 'fly-tipping',
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    my $expected_updates = [
        {
            'service_request_id' => 'case_1',
            'description' => '',
            'external_status_code' => 'Action Scheduled 1',
            'status' => 'action_scheduled',
            'media_url' => '',
            'updated_datetime' => '2023-01-30T17:00:00Z',
            'update_id' => 'case_1_1675098000'
        },
        {
            'description' => '',
            'service_request_id' => 'case_1',
            'external_status_code' => 'Investigating',
            'status' => 'investigating',
            'update_id' => 'case_1_1675094400',
            'updated_datetime' => '2023-01-30T16:00:00Z',
            'media_url' => ''
        }
    ];

    is_deeply decode_json($res->content), $expected_updates, "correct updates returned";

    # Two days later...
    set_fixed_time('2023-02-02T00:00:00Z');

    $endpoint->gather_updates();

    $integration->mock('get_case_summaries_by_filter', sub {
        my ($self, undef, undef, $page_number) = @_;
        if ($page_number == 1) {
            return {
                num_items => 0,
                items => []
            };
        }
        die "unexpected page number: " . $page_number;
    });

    my $next_day_expected_updates = [
        {
            'service_request_id' => 'case_1',
            'description' => '',
            'external_status_code' => 'Closed',
            'status' => 'closed',
            'media_url' => '',
            'updated_datetime' => '2023-02-01T00:00:00Z',
            'update_id' => 'case_1_1675209600'
        },
    ];
    push @$next_day_expected_updates, @$expected_updates;


    $res = $endpoint->run_test_request(
        GET => sprintf('/servicerequestupdates.json?start_date=%s&end_date=%s', $start_date, $end_date),
        jurisdiction_id => 'centralbedfordshire_jadu',
        api_key => 'test',
        service_code => 'fly-tipping',
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content), $next_day_expected_updates, "correct updates returned";
};

done_testing;

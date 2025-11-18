package SOAP::Result;
use Object::Tiny qw(method result);

package Integrations::Verint::Dummy;

use Path::Tiny;
use Moo;
use Test::More;
use Test::MockModule;
use List::Util 'pairs';
use Test::MockTime;

extends 'Integrations::Verint';

my $soap_lite = Test::MockModule->new('SOAP::Lite');
my $create_report_time = '2025-11-18T16:28:30Z';

$soap_lite->mock(call => sub {
    my ($cls, @args) = @_;

    my $call = shift @args;

    if ($call eq 'CreateRequest') {
        is $args[0]->name, 'name';
        is $args[0]->value, 'lle_benches_form';
        is $args[0]->type, 'sch:nonEmptyString';

        is $args[1]->name, 'data';
        is $args[1]->value->[0]->name, 'form-data';
        is $args[1]->type, 'sch:Data';
        my $data = $args[1]->value->[0]->value;
        my @expected = (
            [ 'le_gis_lat', '50' ],
            [ 'le_gis_lon', '0.1' ],
            [ 'txt_easting', '1' ],
            [ 'txt_northing', '2' ],
            [ 'txt_map_usrn', '12345' ],
            [ 'txt_map_uprn', '67899' ],
            [ 'txt_location', 'Property' ],
            [ 'txt_request_open_date', $create_report_time ],
            [ 'le_typekey', 'bench_or_seat_problem' ],
            [ 'txt_cust_info_first_name', 'Bob' ],
            [ 'txt_cust_info_last_name', 'Mould' ],
            [ 'eml_cust_info_email', 'test@example.com' ],
            [ 'txta_problem_details', 'Bench on High Street next to post office' ],
            [ 'txta_problem', 'Back has come off bench' ],
        );
        for my $field ($$data->value->value) {
            my $expected = shift @expected;
            for my $values (pairs ${$field->value}->value) {
                is $values->[0]->value, $expected->[0];
                is $values->[1]->value, $expected->[1];
            };
        }

        return SOAP::Result->new(method => { status => 'success', ref => 12345 });
    } else {
        die "Unknown call $call made";
    }
});

sub _build_config_file { path(__FILE__)->sibling("enfield_verint.yml")->stringify };

package Open311::Endpoint::Integration::Verint::Dummy;
use Path::Tiny;
use Moo;

extends 'Open311::Endpoint::Integration::Verint';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{config_file} = path(__FILE__)->sibling("enfield_verint.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (
    is => 'ro',
    default => 'Integrations::Verint::Dummy',
);

package main;

use strict;
use warnings;
use utf8;

use Test::More;
use Test::MockTime ':all';
use Path::Tiny;
use Open311::Endpoint::Service::UKCouncil;
use JSON::MaybeXS qw(encode_json decode_json);

BEGIN { $ENV{TEST_MODE} = 1; }

my $enfield_endpoint = Open311::Endpoint::Integration::Verint::Dummy->new;

subtest "GET Service List" => sub {
    my $res = $enfield_endpoint->run_test_request( GET => '/services.xml' );

    ok $res->is_success, 'xml success';
};

my @standard = (
    api_key => 'api-key',
    service_code => 'bench_or_seat_problem',
    address_string => '22 Acacia Avenue',
    first_name => 'Bob',
    last_name => 'Mould',
    email => 'test@example.com',
    description => 'Back has come off bench',
    lat => '50',
    long => '0.1',
    'attribute[description]' => 'Back has come off bench',
    'attribute[title]' => 'Bench on High Street next to post office',
    'attribute[report_url]' => 'http://localhost/1',
    'attribute[easting]' => 1,
    'attribute[northing]' => 2,
    'attribute[category]' => '',
    'attribute[fixmystreet_id]' => 1,
    'attribute[usrn]' => '12345',
    'attribute[uprn]' => '67899',
);

subtest "POST report" => sub {
    set_fixed_time($create_report_time);
    my $res = $enfield_endpoint->run_test_request(
        POST => '/requests.json', @standard);
    is $res->code, 200, 'Report submitted ok';
};

done_testing;

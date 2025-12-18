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
      my %test = (
        lle_abandoned_vehicle => {
          typekey => 'abandoned_vehicle',
          system => 'M3',
          title => 'Next to supermarket',
          description => 'Car left on pavement',
        },
        lle_benches_form => {
          typekey => 'bench_or_seat_problem',
          system => 'EXOR',
          title => 'Bench on High Street next to post office',
          description => 'Back has come off bench',
        },
      );
        is $args[0]->name, 'name';
        my $form_name = $args[0]->value;
        my $form_data = $test{$form_name};
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
            [ 'le_typekey', $form_data->{typekey} ],
            [ 'txt_lob_system', $form_data->{system} ],
            [ 'txt_cust_info_first_name', 'Bob' ],
            [ 'txt_cust_info_last_name', 'Mould' ],
            [ 'eml_cust_info_email', 'test@example.com' ],
            [ 'txta_problem', $form_data->{title} . ' - FMS ID: 1' ],
            [ 'txta_problem_details', $form_data->{description} ],
        );

        if ($form_name eq 'lle_abandoned_vehicle') {
          push(@expected, [ 'm3_comments', "Tell us about the problem: Next to supermarket - FMS ID: 1\n\nProblem details: Car left on pavement\n\nLink: http://localhost/1" ] );
        } else {
            push @expected, [ 'txt_company_name', 'Company' ];
        }

        for my $field ($$data->value->value) {
            my $expected = shift @expected;
            for my $values (pairs ${$field->value}->value) {
                is $values->[0]->value, $expected->[0];
                is $values->[1]->value, $expected->[1];
            };
        }
        is scalar @expected, 0, "No unexpected fields";

        return SOAP::Result->new(method => { status => 'success', ref => 12345 });
    } elsif ($call eq 'AttachFileRequest') {
        is $args[0]->value, '12345';
        is $args[1]->value, 'image.jpg';
        is $args[2]->value, 'VGhpcyBpcyBhIGZha2UgaW1hZ2UK';
        is $args[3]->value, 'image/jpeg';
        is $args[4]->value, 'txt_filename';
    } elsif ($call eq 'searchAndRetrieveCaseDetails') {
        my @dates = ${$args[0]->value}->value;
        is $dates[0]->value, '2025-11-18T12:00:00Z';
        is $dates[1]->value, '2025-11-18T13:00:00Z';
        is $args[1]->value, 'all';
        return SOAP::Result->new(method => { FWTCaseFullDetails => [ {
            CoreDetails => {
                ExternalReferences => { ExternalReference => 1 },
                caseCloseureReason => '',
            },
        }, {
            CoreDetails => {
                Closed => '2025-11-18T09:00:00Z',
                ExternalReferences => { ExternalReference => 2 },
                caseCloseureReason => 'Case Resolved (some text)',
            },
        } ] });
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
use HTTP::Request::Common;
use Web::Dispatch::Upload;

BEGIN { $ENV{TEST_MODE} = 1; }

my $enfield_endpoint = Open311::Endpoint::Integration::Verint::Dummy->new;

subtest "GET Service List" => sub {
    my $res = $enfield_endpoint->run_test_request( GET => '/services.xml' );

    ok $res->is_success, 'xml success';
    is $res->decoded_content, <<XML;
<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>Abandoned vehicle</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>abandoned_vehicle</service_code>
    <service_name>Abandoned vehicle</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Bench or seat on the pavement</description>
    <group>Benches</group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>bench_or_seat_problem</service_code>
    <service_name>Bench or seat on the pavement</service_name>
    <type>realtime</type>
  </service>
</services>
XML
};

subtest "GET Service" => sub {
    my $res = $enfield_endpoint->run_test_request( GET => '/services/abandoned_vehicle.xml' );

    ok $res->is_success, 'xml success';
    is $res->decoded_content, <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_definition>
  <attributes>
    <attribute>
      <automated>server_set</automated>
      <code>easting</code>
      <datatype>number</datatype>
      <datatype_description></datatype_description>
      <description>easting</description>
      <order>1</order>
      <required>true</required>
      <variable>false</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>northing</code>
      <datatype>number</datatype>
      <datatype_description></datatype_description>
      <description>northing</description>
      <order>2</order>
      <required>true</required>
      <variable>false</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>fixmystreet_id</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>external system ID</description>
      <order>3</order>
      <required>true</required>
      <variable>false</variable>
    </attribute>
    <attribute>
      <code>emergency</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Ring us</description>
      <order>4</order>
      <required>false</required>
      <variable>false</variable>
    </attribute>
    <attribute>
      <code>pca</code>
      <datatype>singlevaluelist</datatype>
      <datatype_description></datatype_description>
      <description>Park?</description>
      <order>5</order>
      <required>true</required>
      <values>
        <value>
          <name>Yes</name>
          <key>1</key>
        </value>
        <value>
          <name>No</name>
          <key>0</key>
        </value>
      </values>
      <variable>true</variable>
    </attribute>
  </attributes>
  <service_code>abandoned_vehicle</service_code>
</service_definition>
XML
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
    'attribute[company_name]' => 'Company',
);

my @m3_data = (
    api_key => 'api-key',
    service_code => 'abandoned_vehicle',
    address_string => '22 Acacia Avenue',
    first_name => 'Bob',
    last_name => 'Mould',
    email => 'test@example.com',
    description => 'Car left on pavement',
    lat => '50',
    long => '0.1',
    'attribute[description]' => 'Car left on pavement',
    'attribute[title]' => 'Next to supermarket',
    'attribute[report_url]' => 'http://localhost/1',
    'attribute[easting]' => 1,
    'attribute[northing]' => 2,
    'attribute[category]' => '',
    'attribute[fixmystreet_id]' => 1,
    'attribute[pca]' => 0,
    'attribute[usrn]' => '12345',
    'attribute[uprn]' => '67899',
);

subtest "POST report" => sub {
    set_fixed_time($create_report_time);
    my $res = $enfield_endpoint->run_test_request(
        POST => '/requests.json', @standard);
    is $res->code, 200, 'Report submitted ok';
};

subtest "POST M3 report" => sub {
    set_fixed_time($create_report_time);
    my $res = $enfield_endpoint->run_test_request(
        POST => '/requests.json', @m3_data);
    is $res->code, 200, 'Report submitted ok';
};

subtest "POST report with photo" => sub {
    set_fixed_time($create_report_time);

    my $file = Web::Dispatch::Upload->new(
        tempname => path(__FILE__)->dirname . '/files/bartec/image.jpg',
        filename => 'image.jpg',
        size => 10,
    );

    my $req = POST '/requests.json',
        Content_Type => 'form-data',
        Content => [ @standard, uploads => [ $file ] ];
    my $res = $enfield_endpoint->run_test_request($req);

    is $res->code, 200, 'Report submitted ok';
};

subtest 'GET updates' => sub {
    my $res = $enfield_endpoint->run_test_request(
        GET => '/servicerequestupdates.json?start_date=2025-11-18T12:00:00Z&end_date=2025-11-18T13:00:00Z');
    is $res->code, 200, 'Updates fetched ok';
    my $content = decode_json($res->content);
    is_deeply $content, [{
      'status' => 'fixed',
      'update_id' => '2_f57de23c',
      'media_url' => '',
      'description' => '',
      'service_request_id' => 2,
      'updated_datetime' => '2025-11-18T09:00:00Z'
    }];
};

done_testing;

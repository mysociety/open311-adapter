package Open311::Endpoint::Integration::UK::Dummy;
use Moo;
extends 'Open311::Endpoint::Integration::Passthrough';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'passthrough_dummy';
    $args{config_filename} = "dummy"; # For Role::Memcached
    $args{config_data} = "endpoint: URL/\napi_key: 123";
    return $class->$orig(%args);
};

package main;

use strict;
use warnings;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::Output;
use Test::Warn;

use JSON::MaybeXS;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }

my $expected_services = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>Flooding</description>
    <groups>
      <group>Flooding</group>
      <group>Flooding &amp; Drainage</group>
    </groups>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>ABC_DEF</service_code>
    <service_name>Flooding</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Different type of flooding</description>
    <groups>
      <group>Flooding &amp; Drainage</group>
    </groups>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>ABC_DEF_1</service_code>
    <service_name>Different type of flooding</service_name>
    <type>realtime</type>
  </service>
</services>
XML

my $expected_defn = <<XML;
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
  </attributes>
  <service_code>ABC_DEF</service_code>
</service_definition>
XML

my $expected_request_post = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_requests>
  <request>
    <service_request_id>2001</service_request_id>
  </request>
</service_requests>
XML

my $expected_update_post = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <update_id>2002</update_id>
  </request_update>
</service_request_updates>
XML

my $expected_updates = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <description></description>
    <external_status_code>INP</external_status_code>
    <media_url></media_url>
    <service_request_id>2001</service_request_id>
    <status>in_progress</status>
    <update_id>2001_3</update_id>
    <updated_datetime>2018-03-01T12:00:00Z</updated_datetime>
  </request_update>
  <request_update>
    <description></description>
    <external_status_code>INP</external_status_code>
    <media_url></media_url>
    <service_request_id>2002</service_request_id>
    <status>in_progress</status>
    <update_id>2002_1</update_id>
    <updated_datetime>2018-03-01T13:00:00Z</updated_datetime>
  </request_update>
  <request_update>
    <description></description>
    <external_status_code>DUP</external_status_code>
    <media_url></media_url>
    <service_request_id>2002</service_request_id>
    <status>duplicate</status>
    <update_id>2002_2</update_id>
    <updated_datetime>2018-03-01T13:30:00Z</updated_datetime>
  </request_update>
</service_request_updates>
XML

my $expected_requests = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_requests>
  <request>
    <address></address>
    <address_id></address_id>
    <description>this is a report from confirm</description>
    <lat>100</lat>
    <long>100</long>
    <media_url></media_url>
    <requested_datetime>2018-04-17T13:34:56+01:00</requested_datetime>
    <service_code>ABC_DEF</service_code>
    <service_name>Flooding</service_name>
    <service_request_id>2003</service_request_id>
    <status>in_progress</status>
    <updated_datetime>2018-04-17T13:34:56+01:00</updated_datetime>
    <zipcode></zipcode>
  </request>
</service_requests>
XML

my $lwp = Test::MockModule->new('LWP::UserAgent');
$lwp->mock(request => sub {
    my ($ua, $req) = @_;
    return HTTP::Response->new(200, 'OK', [], $expected_services) if $req->uri =~ /services\.xml/;
    return HTTP::Response->new(200, 'OK', [], $expected_defn) if $req->uri =~ /services\/ABC_DEF\.xml/;
    if ($req->method eq 'GET' && $req->uri =~ /servicerequestupdates\.xml/) {
        unlike $req->uri, qr/end_date/;
        return HTTP::Response->new(200, 'OK', [], $expected_updates);
    }
    return HTTP::Response->new(200, 'OK', [], $expected_requests) if $req->method eq 'GET' && $req->uri =~ /requests\.xml/;
    return HTTP::Response->new(200, 'OK', [], $expected_request_post) if $req->method eq 'POST' && $req->uri =~ /requests\.xml/;
    return HTTP::Response->new(200, 'OK', [], $expected_update_post) if $req->method eq 'POST' && $req->uri =~ /servicerequestupdates\.xml/;
});

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

subtest "GET Service List" => sub {
    my $res = $endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
    is $res->content, $expected_services or diag $res->content;
};

subtest "GET Service List Description" => sub {
    my $res = $endpoint->run_test_request( GET => '/services/ABC_DEF.xml' );
    ok $res->is_success, 'xml success';
    is $res->content, $expected_defn or diag $res->content;
};

subtest "POST OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'ABC_DEF',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        'attribute[easting]' => 100,
        'attribute[northing]' => 100,
        'attribute[fixmystreet_id]' => 1001,
        'attribute[title]' => 'Title',
        'attribute[description]' => 'This is the details',
        'attribute[report_url]' => 'http://example.com/report/1001',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 2001
        } ], 'correct json returned';
};

subtest 'POST update' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.xml',
        api_key => 'test',
        service_request_id => 1001,
        update_id => 123,
        first_name => 'Bob',
        last_name => 'Mould',
        description => 'Update here',
        status => 'OPEN',
        updated_datetime => '2016-09-01T15:00:00Z',
        media_url => 'http://example.org/',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is_string $res->content, $expected_update_post, 'xml string ok' or diag $res->content;
};

subtest 'GET update' => sub {
    my $res = $endpoint->run_test_request(
        # No end date to check is okay
        GET => '/servicerequestupdates.xml?start_date=2018-01-01T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is_string $res->content, $expected_updates, 'xml string ok' or diag $res->content;
};

subtest 'GET reports' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/requests.xml?jurisdiction_id=confirm_dummy&start_date=2018-04-17T00:00:00Z&end_date=2018-04-18T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is_string $res->content, $expected_requests, 'xml string ok' or diag $res->content;
};

done_testing;


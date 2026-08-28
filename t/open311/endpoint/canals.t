package Integrations::Rest::Dummy;
use Path::Tiny;
use Moo;
use Test::More;
use Test::MockModule;
use JSON::MaybeXS qw(encode_json decode_json);

extends 'Integrations::Rest';

my $lwp = Test::MockModule->new('LWP::UserAgent');

$lwp->mock(request => sub {
    my ($ua, $req) = @_;
    if ($req->uri =~ /Token/) {
        like $req->uri, qr/example\.com\/api\//, 'api url read from config';
        return HTTP::Response->new(200, 'OK', [], encode_json({ 'access_token' => 'OpenSesame' }));
    } elsif ($req->uri =~ /Incidents$/) {
        is_deeply decode_json($req->content), {
          'longitude' => '0.1',
          'fms_category' => 'aqueduct',
          'type' => 'Administration',
          'status' => 'New',
          'location_description' => '12',
          'region_c' => 'Wales and North East',
          'original_fms_id' => '1',
          'description' => 'Aqueduct is blocked by tree

This is the question: Yes',
          'name' => 'Aqueduct by Potters Bridge is blocked',
          'fms_subcategory' => 'access_issues',
          'priority' => '',
          'resolution' => 'Accepted',
          'media_url' => '',
          'fms_public_url' => 'http://localhost/1',
          'latitude' => '50',
          'latest_fms_id' => '1',
        };
        is $req->header('Authorization'),'Bearer OpenSesame', 'Authorisation header set';
        return HTTP::Response->new(200, 'OK', [], encode_json({ 'id' => 'incident-12345' }));
    } elsif ($req->uri =~ /Incidents\?filter/) {
        is $req->header('Authorization'),'Bearer OpenSesame', 'Authorisation header set';
        return HTTP::Response->new(200, 'OK', [], path(__FILE__)->sibling("/json/sugar/canals_incident.json")->slurp);
    } elsif ($req->uri =~ /Contacts/) {
        is $req->header('Authorization'),'Bearer OpenSesame', 'Authorisation header set';
        return HTTP::Response->new(200, 'OK', [], encode_json({ 'id' => 'user-236' }));
    } elsif ($req->uri =~ /Incidents\/incident-12345\/incidents_case/) {
        is $req->header('Authorization'),'Bearer OpenSesame', 'Authorisation header set';
        return HTTP::Response->new(200, 'OK', [], encode_json({ 'related_record' => { 'id' => 'case-3456' } }));
    }
});

sub _build_config_file { path(__FILE__)->sibling("canals.yml")->stringify };

package Open311::Endpoint::Integration::Sugar::Dummy;
use Path::Tiny;
use Moo;
use HTTP::Response;
use HTTP::Headers;

extends 'Open311::Endpoint::Integration::Sugar';

has integration_class => (
    is => 'ro',
    default => 'Integrations::Rest::Dummy',
);

package main;

use strict; use warnings;

use utf8;

use Test::More;
use Path::Tiny;
use Open311::Endpoint::Service::UKCouncil;
use JSON::MaybeXS qw(encode_json decode_json);

BEGIN { $ENV{TEST_MODE} = 1; }

my $canals_endpoint = Open311::Endpoint::Integration::Sugar::Dummy->new(
    jurisdiction_id => 'canals_sugar',
    config_file => path(__FILE__)->sibling("canals.yml")->stringify,
    );

subtest "GET Service List" => sub {
    my $res = $canals_endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
    is $res->content, '<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>Access issues</description>
    <group>Aqueduct</group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>AccessIssues</service_code>
    <service_name>Access issues (CRT: Aqueduct)</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Fallen trees</description>
    <group>Blocked towpath</group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>FallenTrees</service_code>
    <service_name>Fallen trees (CRT: Blocked towpath)</service_name>
    <type>realtime</type>
  </service>
</services>
', 'Categories fetched';
};

subtest "Check user login" => sub {
    my $res = $canals_endpoint->_do_login('Test', 'User', 'test@example.com');
    ok $canals_endpoint->access_token, 'OpenSesame';
};

subtest "POST report" => sub {
    my $res = $canals_endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'canals',
        api_key => 'api-key',
        media_url => [],
        service_code => 'AccessIssues',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'Aqueduct is blocked by tree',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'Aqueduct is blocked by tree',
        'attribute[title]' => 'Aqueduct by Potters Bridge is blocked',
        'attribute[report_url]' => 'http://localhost/1',
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[category]' => 'Access Issues (CRT: Aqueduct)',
        'attribute[fixmystreet_id]' => 1,
        'attribute[location_description]' => '12',
        'attribute[region_c]' => 'Wales and North East',
        'attribute[Q1]' => 'Yes',
    );
    is $res->code, 200, 'Report submitted ok';
    is_deeply decode_json($res->content), [ { service_request_id => 'incident-12345' } ], 'Id from the Incident';
};

subtest "GET report" => sub {
    my $res = $canals_endpoint->run_test_request
      (
       GET => 'requests.json?jurisdiction_id=dummy&start_date=2019-01-02T00:00:00Z&end_date=2019-01-01T02:00:00Z',
      );
    is $res->code, 200, 'Report created for FMS';
    is_deeply decode_json($res->content), [
                                           {
                                            "zipcode" => "",
                                            "status" => "open",
                                            "service_code" => "FallenTrees",
                                            "address_id" => "",
                                            "service_request_id" => "2354556-8ccc-1111-b0e9-a0d3d106b144",
                                            "lat" => 10,
                                            "address" => "",
                                            "updated_datetime" => "2026-07-31T15:28:45+01:00",
                                            "long" => -1,
                                            "description" => "Tree fallen over towpath",
                                            "media_url" => "",
                                            "service_name" => "Fallen trees (CRT: Blocked towpath)",
                                            "requested_datetime" =>"2026-07-31T15:28:45+01:00"
                                           }
                                          ], 'Id from the Case record';
};

subtest "GET report updates" => sub {

    my $res = $canals_endpoint->run_test_request
      (
       GET => 'servicerequestupdates.json?jurisdiction_id=dummy&start_date=2019-01-02T00:00:00Z&end_date=2019-01-01T02:00:00Z',
      );
    is $res->code, 200, 'Updates fetched for FMS';
    is_deeply decode_json($res->content), [
          {
            'external_status_code' => 'New',
            'status' => 'open',
            'update_id' => '2026-08-03T152845',
            'updated_datetime' => '2026-08-03T15:28:45+01:00',
            'description' => '',
            'media_url' => '',
            'service_request_id' => '2354556-8ccc-1111-b0e9-a0d3d106b144'
          }
        ];
};

done_testing;

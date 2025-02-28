package Open311::Endpoint::Integration::UK::BANES::Passthrough::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::BANES::Passthrough';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("www.banes.gov.uk.yml")->stringify;
    $args{endpoint} = 'bathnes/';
    return $class->$orig(%args);
};

package main;

use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use Test::More;
use Test::MockModule;
use JSON::MaybeXS;
use Path::Tiny;
use Open311::Endpoint::Integration::UK::BANES;

my $test_request = {
  jurisdiction_id => 'dummy',
  api_key => 'api-key',
  service_code => 'passthrough-confirm_graffiti@example.com',
  address_string => '22 Acacia Avenue',
  first_name => 'Bob',
  last_name => 'Mould',
  email => 'test@example.com',
  description => 'title: Tree blocking light detail: Tree overhanging garden and blocking light',
  media_url => ['https://localhost/one.jpeg?123', 'https://localhost/two.jpeg?123'],
  lat => '50',
  long => '0.1',
  'attribute[description]' => 'Tree overhanging garden and blocking light',
  'attribute[title]' => 'Tree blocking light',
  'attribute[report_url]' => 'http://localhost/1',
  'attribute[easting]' => 1,
  'attribute[northing]' => 2,
  'attribute[category]' => 'Trees and woodland',
  'attribute[fixmystreet_id]' => 1,
};

my $test_update_request = {
  api_key => 'test',
  service_request_id => 'passthrough-248',
  update_id => 123,
  first_name => 'Bob',
  last_name => 'Mould',
  description => 'Update here',
  status => 'OPEN',
  updated_datetime => '2016-09-01T15:00:00Z',
};

my $expected_confirm_service_request_post = <<XML;
<?xml version="1.0" encoding="utf-16"?>
<service_requests>
  <request>
    <service_request_id>293944</service_request_id>
    <service_notice>
      The City will inspect and require the responsible party to correct within 24 hours and/or issue a Correction Notice or Notice of Violation of the Public Works Code
    </service_notice>
    <account_id/>
  </request>
</service_requests>
XML

my $expected_confirm_service_update_request_post = <<XML;
<?xml version="1.0" encoding="utf-16"?>
<service_request_updates>
    <request_update>
        <update_id>392732</update_id>
    </request_update>
</service_request_updates>
XML

my $ua = Test::MockModule->new('LWP::UserAgent');
$ua->mock(post => sub {
  if ($_[1] =~ /token\/api/) {
    is $_[2]->{username}, 'FMS', "Username picked up from config";
    is $_[2]->{password}, 'FMSPassword', "Password picked up from config";
    return HTTP::Response->new(200, 'OK', [], '12345678910');
  } elsif ($_[1] =~ /servicerequestupdates.xml/) {
    my ($self, $url, $auth_field, $auth_details, $content_field, $args) = @_;
    is $auth_field, 'Authorization', 'Authorisation header set';
    is $auth_details, 'Bearer 12345678910', 'Authorisation set';
    is $content_field, 'Content', 'Content field set';
    $test_update_request->{uploads} = []; # Added over open311 process
    $test_update_request->{media_url} = []; # Added over open311 process
    $test_update_request->{service_request_id} = '248';
    is_deeply $args, $test_update_request, 'service_request_id has prefix removed';
    return HTTP::Response->new(200, 'OK', ["Content-Type", "application/xml"], $expected_confirm_service_update_request_post);
  } else {
    my ($self, $url, $auth_field, $auth_details, $content_field, $args) = @_;
    is $auth_field, 'Authorization', 'Authorisation header set';
    is $auth_details, 'Bearer 12345678910', 'Authorisation set';
    is $content_field, 'Content', 'Content field set';
    $test_request->{uploads} = []; # Added over open311 process
    delete $test_request->{jurisdiction_id}; # Banes are not accepting a jurisdiciton_id so removed before sending
    $test_request->{service_code} = 'confirm_graffiti'; # Service code is now the Confirm service code
    is_deeply $args, $test_request, 'Content set';
    return HTTP::Response->new(200, 'OK', ["Content-Type", "application/xml"], $expected_confirm_service_request_post);
  }
});

use_ok 'Open311::Endpoint::Integration::UK::BANES::Passthrough';

my $endpoint = Open311::Endpoint::Integration::UK::BANES::Passthrough::Dummy->new;

subtest 'POST service request' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        %{ $test_request }
    );

    ok $res->is_success, 'valid request' or diag $res->content;
    is_deeply decode_json($res->content), [ { service_request_id => '293944' } ], 'correct return';
};

subtest 'POST service request update' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        %{ $test_update_request },
    );

    ok $res->is_success, 'valid request' or diag $res->content;
};

subtest 'Check correct integration selected' => sub {
    my $multi = Open311::Endpoint::Integration::UK::BANES->new;
    my @return;
    for my $test (
      [ 'test@example.com', 'Passthrough', 'service'],
      [ 'testexample.com', 'Confirm', 'service'],
      [ 'test@examplecom', 'Confirm', 'service'],
      [ 'passthrough-234', 'Passthrough', 'request'],
      [ '234', 'Confirm', 'request'],
    ) {
      @return = $multi->_map_from_new_id($test->[0], $test->[2]);
      is $return[0], $test->[1], "Correct integration selected" ;
    };
};

done_testing;

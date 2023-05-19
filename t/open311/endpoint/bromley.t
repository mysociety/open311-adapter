# Override the original to provide a config_file
package Open311::Endpoint::Integration::UK::Bromley::Echo;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Echo';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bromley_dummy';
    $args{config_file} = path(__FILE__)->sibling("echo.yml")->stringify;
    return $class->$orig(%args);
};

package main;

use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use Test::More;
use Test::MockModule;
use JSON::MaybeXS;

my $pt = Test::MockModule->new('Open311::Endpoint::Integration::UK::Bromley::Passthrough');
$pt->mock(endpoint => sub { '' });

use_ok 'Open311::Endpoint::Integration::UK::Bromley';

my $endpoint = Open311::Endpoint::Integration::UK::Bromley->new;

subtest "Get service definition with no prefix" => sub {
    my $res = $endpoint->run_test_request( GET => '/services/2104.json' );
    ok $res->is_success, 'valid request' or diag $res->content;
    is_deeply decode_json($res->content), {
          'service_code' => '2104',
          'attributes' => [
            {
              'variable' => 'true',
              'datatype_description' => '',
              'datatype' => 'string',
              'automated' => 'hidden_field',
              'code' => 'uprn',
              'description' => 'UPRN reference',
              'order' => 1,
              'required' => 'false'
            },
            {
              'order' => 2,
              'code' => 'property_id',
              'description' => 'Property ID',
              'datatype_description' => '',
              'datatype' => 'string',
              'automated' => 'hidden_field',
              'required' => 'false',
              'variable' => 'true'
            },
            {
              'order' => 3,
              'code' => 'service_id',
              'description' => 'Service ID',
              'datatype_description' => '',
              'datatype' => 'string',
              'automated' => 'hidden_field',
              'required' => 'false',
              'variable' => 'true'
            },
            {
              'required' => 'true',
              'datatype_description' => '',
              'datatype' => 'string',
              'automated' => 'server_set',
              'variable' => 'false',
              'order' => 4,
              'code' => 'fixmystreet_id',
              'description' => 'external system ID'
            }
          ]
        }, 'correct json returned';
};

my $expected_update_post = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <update_id>2002</update_id>
  </request_update>
</service_request_updates>
XML
my $lwp = Test::MockModule->new('LWP::UserAgent');
$lwp->mock(request => sub {
    my ($ua, $req) = @_;
    like $req->as_string, qr/status=OPEN/, 'Has OPEN status sent through';
    return HTTP::Response->new(200, 'OK', [], $expected_update_post);
});

my $update_data = {
    jurisdiction_id => 'bromley',
    service_code => 'WINTER_SNOW',
    api_key => 'test',
    service_request_id => 1001,
    update_id_ext => 123,
    first_name => 'Bob',
    last_name => 'Mould',
    description => 'Update here',
    updated_datetime => '2016-09-01T15:00:00Z',
    media_url => 'http://example.org/',
};

subtest 'POST update' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.xml',
        %$update_data,
        status => 'OPEN',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is $res->content, $expected_update_post, 'xml string ok' or diag $res->content;
};

subtest 'POST update' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.xml',
        %$update_data,
        status => 'CLOSED',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is $res->content, $expected_update_post, 'xml string ok' or diag $res->content;
};

done_testing;

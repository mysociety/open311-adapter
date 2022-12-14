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
              'code' => 'service_id',
              'description' => 'Service ID',
              'datatype_description' => '',
              'datatype' => 'string',
              'automated' => 'server_set',
              'required' => 'false',
              'variable' => 'true'
            },
            {
              'required' => 'true',
              'datatype_description' => '',
              'datatype' => 'string',
              'automated' => 'server_set',
              'variable' => 'false',
              'order' => 3,
              'code' => 'fixmystreet_id',
              'description' => 'external system ID'
            }
          ]
        }, 'correct json returned';
};

done_testing;

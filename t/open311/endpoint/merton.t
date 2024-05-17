# Override the original to provide a config_file
package Open311::Endpoint::Integration::UK::Merton::Echo;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Echo';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'merton_dummy';
    $args{config_file} = path(__FILE__)->sibling("merton.yml")->stringify;
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

my $pt = Test::MockModule->new('Open311::Endpoint::Integration::UK::Merton::Passthrough');
$pt->mock(endpoint => sub { '' });

my $ua = Test::MockModule->new('LWP::UserAgent');
$ua->mock(get => sub {
    my $file;
    if ($_[1] eq 'services.xml') {
        $file = 'xml/merton/services.xml';
    } elsif ($_[1] eq 'services/TEST.xml') {
        $file = 'xml/merton/service.xml';
    } elsif ($_[1] eq 'tokens/TOKEN.xml') {
        $file = 'xml/merton/token.xml';
    }
    return HTTP::Response->new(200, 'OK', [], path(__FILE__)->sibling($file)->slurp);
});
$ua->mock(post => sub {
    my $file = 'xml/merton/requestpost.xml';
    return HTTP::Response->new(200, 'OK', [], path(__FILE__)->sibling($file)->slurp);
});

use_ok 'Open311::Endpoint::Integration::UK::Merton';

my $endpoint = Open311::Endpoint::Integration::UK::Merton->new;

subtest "Get service definition with no prefix" => sub {
    my $res = $endpoint->run_test_request( GET => '/services/1635.json' );
    ok $res->is_success, 'valid request' or diag $res->content;
    my $i = 1;
    is_deeply decode_json($res->content), {
          'service_code' => '1635',
          'attributes' => [
            (map { {
              'automated' => 'hidden_field',
              'datatype_description' => '',
              'datatype' => 'string',
              'order' => $i++,
              'required' => 'false',
              'variable' => 'true',
              %$_,
            } }
            { 'code' => 'uprn', 'description' => 'UPRN reference', },
            { 'code' => 'property_id', 'description' => 'Property ID', },
            { 'code' => 'service_id', 'description' => 'Service ID', },
            {
              'required' => 'true',
              'automated' => 'server_set',
              'variable' => 'false',
              'code' => 'fixmystreet_id',
              'description' => 'external system ID'
            },
            { 'code' => 'Action', 'description' => 'Action' },
            { 'code' => 'Container_Type', 'description' => 'Container_Type' },
            { 'code' => 'Notes', 'description' => 'Notes' },
            { 'code' => 'Reason', 'description' => 'Reason' },
    ),
          ]
        }, 'correct json returned';
};


subtest "Get service definition with a group" => sub {
    my $res = $endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'valid request' or diag $res->content;
    my @codes = $res->content =~ /<service_code>(.*?)<\/service_code>/g;
    is_deeply \@codes, [  '1565-add', '1635', '1636', '1638', 'missed', 'GR' ];

    $res = $endpoint->run_test_request( GET => '/services/TEST.json' );
    ok $res->is_success, 'valid request' or diag $res->content;
    my $i = 1;
    is_deeply decode_json($res->content), {
          'service_code' => 'TEST',
          'attributes' => [
            (map { {
              'automated' => 'hidden_field',
              'datatype' => 'string',
              'datatype_description' => '',
              'order' => $i++,
              'required' => 'true',
              'variable' => 'true',
              'description' => '',
              'code' => $_,
            } } qw/service usrn/),
            (map { {
              'automated' => 'server_set',
              'datatype' => 'string',
              'datatype_description' => '',
              'order' => $i++,
              'required' => 'false',
              'variable' => 'false',
              %$_,
            } }
            { 'code' => 'fixmystreet_id', 'description' => 'FixMyStreet ID', required => 'true' },
            { 'code' => 'easting', 'description' => 'Easting', datatype => 'number' },
            { 'code' => 'northing', 'description' => 'Northing', datatype => 'number' },
            { 'code' => 'closest_address', 'description' => 'Closest address' },
            ),
          ]
        }, 'correct json returned';
};

subtest "Post a report, get a token" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'TEST',
        address_string => 'address',
        'attribute[service]' => 1234,
        'attribute[usrn]' => 1234,
        'attribute[fixmystreet_id]' => 1001,
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is_deeply decode_json($res->content), [ { "token" => 'TOKEN' } ];
};

subtest "Convert a token to an ID" => sub {
    my $res = $endpoint->run_test_request( GET => "/tokens/TOKEN.json" );
    ok $res->is_success, 'valid request' or diag $res->content;
    is_deeply decode_json($res->content), [ { "service_request_id" => 'ServiceID' } ];
};

done_testing;

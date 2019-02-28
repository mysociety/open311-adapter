package Mock::Response;

use Moo;
use Encode;
use Types::Standard ':all';
use utf8;

has content => (
    is => 'ro',
    isa => Str,
    default => '[]',
    coerce => sub { encode_utf8($_[0]) }
);

has code => (
    is => 'ro',
    isa => Str,
    default => '200',
);

has message => (
    is => 'ro',
    isa => Str,
    default => 'OK',
);

has is_success => (
    is => 'ro',
    isa => Bool,
    default => 1
);

package Integrations::Alloy::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Alloy';
with 'Role::Config';
has config_filename => ( is => 'ro', default => 'dummy' );
sub _build_config_file { path(__FILE__)->sibling("alloy.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Alloy';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("alloy.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Alloy::Dummy');
sub jurisdiction_id { return 'dummy'; }
has service_request_content => (is => 'ro', default => '/open311/service_request_extended');

package main;

use strict; use warnings;

use utf8;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::MockTime ':all';
use Encode;

use Open311::Endpoint;
use Data::Dumper;
use JSON::MaybeXS;
use Path::Tiny;

use Open311::Endpoint::Integration::UK;

my $endpoint = Open311::Endpoint::Integration::UK->new;

my %responses = (
    resource => '{
    }',
);

my @sent;
my @calls;

my $integration = Test::MockModule->new('Integrations::Alloy');
$integration->mock('api_call', sub {
    my ($self, $call, $params, $body) = @_;

    my $content = '[]';
    push @calls, $call;
    if ( $body ) {
        push @sent, $body;
        if ( $call eq 'resource' ) {
            $content = '{ "resourceId": 12345 }';
        } elsif ( $call eq 'search/resource-fetch' ) {
            my $type = $body->{aqsNode}->{properties}->{entityCode};
            my $time = $body->{aqsNode}->{children}->[0]->{children}->[1]->{properties}->{value}->[0];
            if ( $type =~ /DEFECT/ ) {
                if ( $time =~ /2019-01-02/ ) {
                    $content = path(__FILE__)->sibling('json/alloy/defect_search_all.json')->slurp;
                } else {
                    $content = path(__FILE__)->sibling('json/alloy/defect_search.json')->slurp;
                }
            } else {
                $content = path(__FILE__)->sibling('json/alloy/inspect_search.json')->slurp;
            }
        }
    } else {
        if ( $call eq 'reference/value-type' ) {
            $content = path(__FILE__)->sibling('json/alloy/reference_value_type.json')->slurp;
        } elsif ( $call eq 'source-type' ) {
            $content = path(__FILE__)->sibling('json/alloy/source_type.json')->slurp;
        } elsif ( $call eq 'source' ) {
            $content = path(__FILE__)->sibling('json/alloy/source.json')->slurp;
        } elsif ( $call eq 'resource/3027029/parents' ) {
            $content = '{ "details": { "parents": [] } }';
        } elsif ( $call eq 'resource/3027029/versions' ) {
            $content = path(__FILE__)->sibling('json/alloy/resource_versions.json')->slurp;
        } elsif ( $call eq 'resource/4947502/versions' ) {
            $content = path(__FILE__)->sibling('json/alloy/resource_versions_4947502.json')->slurp;
        } elsif ( $call eq 'resource/1' ) {
            $content = '{ "sourceTypeId": 800 }';
        } elsif ( $call eq 'source-type/800/linked-source-types' ) {
            $content = path(__FILE__)->sibling('json/alloy/linked_source_types.json')->slurp;
        } elsif ( $call eq 'projection/point' ) {
            $content = '{ "x": 1, "y": 2 }';
        } elsif ( $call =~ m#resource/[0-9]*/parents# ) {
            $content = '{ "details": { "parents": [] } }';
        } elsif ( $call =~ m#resource/[0-9]*/versions# ) {
            $content = path(__FILE__)->sibling('json/alloy/resource_versions_all.json')->slurp;
        } else {
            $content = $responses{$call};
        }
    }

    $content ||= '[]';

    my $result = decode_json(encode_utf8($content));
    return $result;
});

subtest "create basic problem" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request( 
        POST => '/requests.json', 
        jurisdiction_id => 'dummy',
        api_key => 'test',
        service_code => 'Kerbs_Missing',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[title]' => '1',
        'attribute[report_url]' => 'http://localhost/1',
        'attribute[asset_resource_id]' => 1,
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[category]' => 'Kerbs_Missing',
        'attribute[fixmystreet_id]' => 1,
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;


    is_deeply $sent,
    {
    attributes =>         {
        1001546 => [
            {
                command => "add",
                resourceId => 1
            }
        ],
        1001825 => [
            {
                command => "add",
                resourceId => 708823
            }
        ],
        1009855 => 1,
        1009856 => "FixMyStreet",
        1009857 => "Request for Service",
        1009858 => [ { resourceId => 6183644, command => "add" } ],
        1009859 => 1,
        1009860 => "description",
        1009861 => "2014-01-01T12:00:00Z"
    },
    geoJson => {
        coordinates => [
            1,
            2
        ],
        type => "Point"
    },
    networkReference => undef,
    parents => {
        1009847 => [
            1
        ]
    },
    sourceId => 2590
    }
    , 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 12345
        } ], 'correct json returned';

};

subtest "create problem with no resource_id" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request( 
        POST => '/requests.json', 
        jurisdiction_id => 'dummy',
        api_key => 'test',
        service_code => 'Kerbs_Missing',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[title]' => '1',
        'attribute[report_url]' => 'http://localhost/1',
        'attribute[asset_resource_id]' => '',
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[category]' => 'Kerbs_Missing',
        'attribute[fixmystreet_id]' => 1,
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;


    is_deeply $sent,
    {
    attributes =>         {
        1001546 => [
            {
                command => "add",
                resourceId => 1
            }
        ],
        1001825 => [
            {
                command => "add",
                resourceId => 708823
            }
        ],
        1009855 => 1,
        1009856 => "FixMyStreet",
        1009857 => "Request for Service",
        1009858 => [ { resourceId => 6183644, command => "add" } ],
        1009859 => 1,
        1009860 => "description",
        1009861 => "2014-01-01T12:00:00Z"
    },
    geoJson => {
        coordinates => [
            1,
            2
        ],
        type => "Point"
    },
    networkReference => undef,
    parents => {},
    sourceId => 2590
    }
    , 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 12345
        } ], 'correct json returned';

};

subtest "check fetch updates" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=dummy&start_date=2019-01-01T00:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [ {
        status => 'investigating',
        service_request_id => '3027029',
        description => '',
        updated_datetime => '2014-01-01T11:59:40Z',
        update_id => '271882',
        media_url => '',
    },
    {
        status => 'investigating',
        service_request_id => '4947502',
        description => '',
        updated_datetime => '2019-02-19T09:11:08Z',
        update_id => '271877',
        media_url => '',
        fixmystreet_id => '10034',
    } ], 'correct json returned';
};

subtest "check fetch problem" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
      GET => '/requests.json?jurisdiction_id=dummy&start_date=2019-01-02T00:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [{
      updated_datetime => "2014-01-01T12:00:00Z",
      service_code => "Grit Bin - damaged/replacement",
      requested_datetime => "2019-02-19T11:26:26Z",
      long => 1,
      address => "",
      status => "investigating",
      media_url => "",
      zipcode => "",
      description => "test",
      service_request_id => 4947504,
      lat => 2,
      address_id => "",
      service_name => "Grit Bin - damaged/replacement"
   },
   {
      long => 1,
      requested_datetime => "2019-02-19T11:29:16Z",
      service_code => "Shelter Damaged",
      updated_datetime => "2014-01-01T12:00:00Z",
      service_name => "Shelter Damaged",
      address_id => "",
      lat => 2,
      description => "test",
      service_request_id => 4947505,
      zipcode => "",
      media_url => "",
      status => "investigating",
      address => ""
   },
   {
      address_id => "",
      lat => 2,
      service_request_id => 4947597,
      description => "fill",
      service_name => "Grit Bin - empty/refill",
      status => "fixed",
      media_url => "",
      address => "",
      zipcode => "",
      requested_datetime => "2019-02-21T14:44:53Z",
      long => 1,
      updated_datetime => "2014-01-01T12:00:00Z",
      service_code => "Grit Bin - empty/refill"
   }], "correct json returned";
};


restore_time();
done_testing;
